import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Holds what the settings window shows. Every edit is written straight to config.json.
final class SettingsModel: ObservableObject {
    @Published private(set) var file = ConfigFile.default
    @Published private(set) var error: String?
    @Published var accessibilityGranted = false
    @Published private(set) var launchAtLogin = false
    var onSave: (() -> Void)?

    func apply(_ newFile: ConfigFile) {
        if newFile != file { file = newFile }
        error = nil
    }

    func showError(_ message: String) { error = message }

    func set(_ action: CornerAction?, for corner: Corner) {
        var newFile = file
        newFile.corners[corner] = action
        save(newFile)
    }

    func setZone(_ zone: Double) {
        var newFile = file
        newFile.zone = (zone * 100).rounded() / 100
        if newFile != file { save(newFile) }
    }

    func resetToDefaults() { save(.default) }

    private func save(_ newFile: ConfigFile) {
        file = newFile
        do {
            try Config.write(newFile)
        } catch let saveError {
            error = "Could not save settings: \(saveError.localizedDescription)"
            return
        }
        onSave?()
    }

    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("SML Corners: login item: %@", error.localizedDescription)
        }
        refreshLaunchAtLogin()
    }
}

/// The friendly choices shown in each corner's menu, mapped onto config action types.
enum Choice: Hashable {
    case nothing, screenshotAreaClipboard, screenshotAreaFile, screenshotScreenClipboard
    case app, website, shortcut, command

    private static let presetKeys: [Choice: String] = [
        .screenshotAreaClipboard: "ctrl+shift+cmd+4",
        .screenshotAreaFile: "shift+cmd+4",
        .screenshotScreenClipboard: "ctrl+shift+cmd+3",
    ]

    init(_ action: CornerAction?) {
        guard let action else { self = .nothing; return }
        switch action.type {
        case "app": self = .app
        case "url": self = .website
        case "shell": self = .command
        default:
            self = Choice.presetKeys.first { Keys.same($0.value, action.keys) }?.key ?? .shortcut
        }
    }

    var title: String {
        switch self {
        case .nothing: return "Do nothing"
        case .screenshotAreaClipboard: return "Screenshot an area to clipboard"
        case .screenshotAreaFile: return "Screenshot an area to a file"
        case .screenshotScreenClipboard: return "Screenshot whole screen to clipboard"
        case .app: return "Open an app"
        case .website: return "Open a website"
        case .shortcut: return "Press a keyboard shortcut"
        case .command: return "Run a command (advanced)"
        }
    }

    /// A fresh action for this choice, keeping any per-corner zone the old one had.
    func makeAction(replacing old: CornerAction?) -> CornerAction? {
        var action: CornerAction
        switch self {
        case .nothing: return nil
        case .screenshotAreaClipboard, .screenshotAreaFile, .screenshotScreenClipboard:
            action = CornerAction(type: "keystroke", keys: Choice.presetKeys[self])
        case .app: action = CornerAction(type: "app")
        case .website: action = CornerAction(type: "url")
        case .shortcut: action = CornerAction(type: "keystroke")
        case .command: action = CornerAction(type: "shell")
        }
        action.zone = old?.zone
        return action
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var confirmingReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !model.accessibilityGranted { PermissionBanner() }
            if let error = model.error {
                Banner(symbol: "xmark.octagon.fill", color: .red, title: "Settings file has a problem",
                       message: error, button: "Reset to Defaults", action: model.resetToDefaults)
            }

            HStack(spacing: 20) {
                TrackpadPreview(zone: model.file.zone, bound: Set(model.file.corners.keys))
                    .frame(width: 200)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Trackpad corners").font(.title2.bold())
                    Text("Press down in a corner with one finger until it clicks. The action runs when you let go.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    CornerCard(corner: .topLeft, model: model)
                    CornerCard(corner: .topRight, model: model)
                }
                GridRow {
                    CornerCard(corner: .bottomLeft, model: model)
                    CornerCard(corner: .bottomRight, model: model)
                }
            }
            .disabled(model.error != nil)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("Corner size")
                    Slider(value: Binding(get: { model.file.zone }, set: model.setZone), in: 0.06...0.25) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("Small").font(.caption)
                    } maximumValueLabel: {
                        Text("Large").font(.caption)
                    }
                    Text("\(Int((model.file.zone * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
                Toggle("Start SML Corners when I log in", isOn: Binding(
                    get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                HStack {
                    Button("Reset to Defaults…") { confirmingReset = true }
                    Spacer()
                    Button("Open Settings File") { Config.openInEditor() }
                        .buttonStyle(.link)
                }
            }
            .disabled(model.error != nil)
        }
        .padding(20)
        .frame(width: 640)
        .confirmationDialog("Reset all corners to the defaults?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { model.resetToDefaults() }
        } message: {
            Text("Top right takes a screenshot, top left opens Chrome, and the bottom corners do nothing.")
        }
    }
}

private struct CornerCard: View {
    let corner: Corner
    @ObservedObject var model: SettingsModel

    private var action: CornerAction? { model.file.corners[corner] }
    private var incomplete: Bool { action.map { (try? Config.action(from: $0)) == nil } ?? false }

    private var choice: Binding<Choice> {
        Binding(
            get: { Choice(action) },
            set: { new in
                guard new != Choice(action) else { return }
                model.set(new.makeAction(replacing: action), for: corner)
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(corner.title, systemImage: corner.symbol).font(.headline)
                Spacer()
                if incomplete {
                    Text("Not set up yet").font(.caption).foregroundStyle(.orange)
                }
            }
            Picker("Action", selection: choice) {
                Text(Choice.nothing.title).tag(Choice.nothing)
                Divider()
                ForEach([Choice.screenshotAreaClipboard, .screenshotAreaFile, .screenshotScreenClipboard], id: \.self) {
                    Text($0.title).tag($0)
                }
                Divider()
                ForEach([Choice.app, .website, .shortcut], id: \.self) {
                    Text($0.title).tag($0)
                }
                Divider()
                Text(Choice.command.title).tag(Choice.command)
            }
            .labelsHidden()

            detail

            if !corner.isTop && action != nil {
                Text("You often click here by habit, so normal clicks in this corner will be used up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
    }

    @ViewBuilder private var detail: some View {
        switch Choice(action) {
        case .nothing:
            hint("Clicks in this corner work normally.")
        case .screenshotAreaClipboard:
            hint("Drag to select an area. It's copied, ready to paste.")
        case .screenshotAreaFile:
            hint("Drag to select an area. It's saved like a normal screenshot.")
        case .screenshotScreenClipboard:
            hint("Copies the whole screen, ready to paste.")
        case .app:
            AppPicker(action: action) { bundleId, path in
                update { $0.bundleId = bundleId; $0.path = path }
            }
        case .website:
            TextField("example.com", text: field(\.url))
        case .shortcut:
            ShortcutRecorder(keys: action?.keys) { keys in update { $0.keys = keys } }
        case .command:
            TextField("say hello", text: field(\.command))
                .font(.system(.body, design: .monospaced))
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func field(_ path: WritableKeyPath<CornerAction, String?>) -> Binding<String> {
        Binding(
            get: { action?[keyPath: path] ?? "" },
            set: { value in update { $0[keyPath: path] = value.isEmpty ? nil : value } })
    }

    private func update(_ change: (inout CornerAction) -> Void) {
        guard var updated = action else { return }
        change(&updated)
        model.set(updated, for: corner)
    }
}

private struct AppPicker: View {
    let action: CornerAction?
    let onPick: (_ bundleId: String?, _ path: String?) -> Void

    var body: some View {
        let app = AppInfo(action)
        HStack(spacing: 8) {
            if let app {
                Image(nsImage: app.icon).resizable().frame(width: 20, height: 20)
                Text(app.name).lineLimit(1)
            } else if action?.bundleId != nil || action?.path != nil {
                Text("App not found").foregroundStyle(.orange)
            } else {
                Text("No app chosen").foregroundStyle(.secondary)
            }
            Spacer()
            Button(app == nil ? "Choose App…" : "Change…", action: choose)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bundleId = Bundle(url: url)?.bundleIdentifier
        onPick(bundleId, bundleId == nil ? url.path : nil)
    }
}

private struct AppInfo {
    let name: String
    let icon: NSImage

    init?(_ action: CornerAction?) {
        guard let action else { return nil }
        let url = action.bundleId.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            ?? action.path.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        let display = FileManager.default.displayName(atPath: url.path)
        name = display.hasSuffix(".app") ? String(display.dropLast(4)) : display
        icon = NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Click, then press a key combination to record it. Esc cancels.
private struct ShortcutRecorder: View {
    let keys: String?
    let onRecord: (String) -> Void
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(monitor != nil ? "Press keys now…" : (keys.flatMap(Keys.display) ?? "No shortcut"))
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(monitor != nil || keys == nil ? .secondary : .primary)
                Spacer()
                Button(monitor != nil ? "Cancel" : "Record…") { monitor == nil ? start() : stop() }
            }
            Text("Screenshot shortcuts can't be recorded; use the screenshot options instead.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if event.keyCode == 53 && modifiers.isEmpty {
                stop()
            } else if let recorded = Keys.string(code: event.keyCode, modifiers: modifiers) {
                onRecord(recorded)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct TrackpadPreview: View {
    let zone: Double
    let bound: Set<Corner>

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Color(nsColor: .quaternaryLabelColor)
                ForEach(Corner.allCases) { corner in
                    let width = size.width * zone, height = size.height * zone
                    Rectangle()
                        .fill(bound.contains(corner) ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: width, height: height)
                        .position(
                            x: corner.isLeft ? width / 2 : size.width - width / 2,
                            y: corner.isTop ? height / 2 : size.height - height / 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
        }
        .aspectRatio(1.6, contentMode: .fit)
        .accessibilityLabel("Trackpad with active corners highlighted")
    }
}

private struct PermissionBanner: View {
    var body: some View {
        Banner(symbol: "exclamationmark.triangle.fill", color: .orange, title: "One more step",
               message: "Turn on SML Corners in Privacy & Security → Accessibility so it can detect corner clicks.",
               button: "Open Accessibility Settings") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

private struct Banner: View {
    let symbol: String
    let color: Color
    let title: String
    let message: String
    let button: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                Text(message).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(button, action: action)
        }
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}
