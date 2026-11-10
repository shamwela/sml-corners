import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let tap = ClickTap()
    private var configModified: Date?
    private var configError: String?
    private var touchError: String?
    private var tapRunning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = NSImage(
            systemSymbolName: "viewfinder", accessibilityDescription: "SML Corners")

        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Config", action: #selector(openConfig), keyEquivalent: "")
        menu.addItem(withTitle: "Reload", action: #selector(reload), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        try? Config.createIfMissing()
        loadConfig()
        startTouches()
        startTap(prompt: true)
        registerLoginItemOnce()

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

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: Config.url.path))?[.modificationDate] as? Date
    }

    private func loadConfig() {
        configModified = modificationDate()
        do {
            tap.bindings = try Config.load()
            configError = nil
        } catch {
            // Keep the last good bindings.
            configError = "Config error: \(error)"
            NSLog("SML Corners: %@", configError!)
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
            ? "Grant Accessibility in System Settings"
            : touchError ?? configError
        statusLine.title = problem ?? "Running (\(tap.bindings.count) corners bound)"
        statusItem.button?.appearsDisabled = problem != nil
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

    @objc private func openConfig() {
        try? Config.createIfMissing()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-t", Config.url.path]
        try? process.run()
    }

    @objc private func reload() {
        loadConfig()
        startTouches()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
