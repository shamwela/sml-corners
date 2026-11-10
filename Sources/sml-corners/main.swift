import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let tap = ClickTap()
    private let settings = SettingsModel()
    private var settingsWindow: NSWindow?
    private var configModified: Date?
    private var configError: String?
    private var touchError: String?
    private var tapRunning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        statusItem.button?.image = NSImage(
            systemSymbolName: "viewfinder", accessibilityDescription: "SML Corners")

        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Open Settings File", action: #selector(openConfig), keyEquivalent: "")
        menu.addItem(withTitle: "Reload", action: #selector(reload), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit SML Corners", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        settings.onSave = { [weak self] in self?.loadConfig() }
        try? Config.createIfMissing()
        loadConfig()
        startTouches()
        startTap(prompt: true)
        registerLoginItemOnce()
        settings.refreshLaunchAtLogin()

        if !UserDefaults.standard.bool(forKey: "settingsShown") {
            UserDefaults.standard.set(true, forKey: "settingsShown")
            openSettings()
        }

        // Hot reload: pick up config edits, and retry the event tap until Accessibility is granted.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.modificationDate() != self.configModified { self.loadConfig() }
            if !self.tapRunning { self.startTap(prompt: false) }
        }
        // Touch callbacks can go quiet after sleep; reattach on wake.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.startTouches() }
    }

    /// Opening the app again (Finder, Launchpad, Spotlight) while it runs shows settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: Config.url.path))?[.modificationDate] as? Date
    }

    private func loadConfig() {
        configModified = modificationDate()
        do {
            let file = try Config.read()
            let (bindings, errors) = Config.bindings(from: file)
            tap.bindings = bindings
            configError = nil
            // Incomplete corners (e.g. no app chosen yet) are shown in the settings window, not as an error.
            for error in errors { NSLog("SML Corners: skipped %@", error) }
            settings.apply(file)
        } catch {
            // Keep the last good bindings.
            configError = "Settings file error: \(error)"
            NSLog("SML Corners: %@", configError!)
            settings.showError("\(error)")
        }
        updateStatus()
    }

    private func startTouches() {
        switch TouchMonitor.shared.start() {
        case nil: touchError = "Trackpad access unavailable on this macOS"
        case 0?: touchError = "No trackpad found"
        default: touchError = nil
        }
        updateStatus()
    }

    private func startTap(prompt: Bool) {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        tapRunning = AXIsProcessTrustedWithOptions(options) && tap.start()
        updateStatus()
    }

    private func updateStatus() {
        let problem = !tapRunning
            ? "Needs Accessibility permission"
            : touchError ?? configError
        let count = tap.bindings.count
        statusLine.title = problem ?? "Running (\(count) corner\(count == 1 ? "" : "s") active)"
        statusItem.button?.appearsDisabled = problem != nil
        if settings.accessibilityGranted != tapRunning { settings.accessibilityGranted = tapRunning }
    }

    private func registerLoginItemOnce() {
        let key = "loginItemRegistered"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            NSLog("SML Corners: login item: %@", error.localizedDescription)
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: settings)))
            window.title = "SML Corners"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settings.refreshLaunchAtLogin()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openConfig() {
        Config.openInEditor()
    }

    @objc private func reload() {
        loadConfig()
        startTouches()
    }

    /// A menu-bar-only app has no main menu, which would break ⌘C/⌘V/⌘W in the settings window.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit SML Corners", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "SML Corners", action: nil, keyEquivalent: "").submenu = appMenu

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        return main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
