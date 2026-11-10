import AppKit

enum Actions {
    static func run(_ action: ActionKind) {
        switch action {
        case .keystroke(let code, let flags):
            let source = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
                event?.flags = flags
                event?.post(tap: .cghidEventTap)
            }

        case .app(let bundleId, let path):
            let workspace = NSWorkspace.shared
            let url = bundleId.flatMap { workspace.urlForApplication(withBundleIdentifier: $0) }
                ?? path.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            guard let url else {
                NSLog("SML Corners: app not found (%@)", bundleId ?? path ?? "")
                return
            }
            // Already frontmost: do nothing.
            if workspace.frontmostApplication?.bundleURL?.standardizedFileURL == url.standardizedFileURL {
                return
            }
            workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error { NSLog("SML Corners: %@", error.localizedDescription) }
            }

        case .url(let url):
            NSWorkspace.shared.open(url)

        case .shell(let command):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            do { try process.run() } catch { NSLog("SML Corners: %@", error.localizedDescription) }
        }
    }
}
