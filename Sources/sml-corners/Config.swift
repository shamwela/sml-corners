import AppKit
import CoreGraphics
import Foundation

enum Corner: String, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }
    var isTop: Bool { self == .topLeft || self == .topRight }
    var isLeft: Bool { self == .topLeft || self == .bottomLeft }

    var title: String {
        switch self {
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        }
    }

    var symbol: String { "arrow.\(isTop ? "up" : "down").\(isLeft ? "left" : "right")" }
}

/// What a corner does. Add a case here (and in `Config.action(from:)`) to add an action type.
enum ActionKind {
    case keystroke(CGKeyCode, CGEventFlags)
    case app(bundleId: String?, path: String?)
    case url(URL)
    case shell(String)
}

struct CornerBinding {
    let zone: Double
    let action: ActionKind
}

struct ConfigError: Error, CustomStringConvertible {
    let description: String
}

/// One corner's entry in config.json, exactly as stored.
struct CornerAction: Codable, Equatable {
    var type: String
    var keys: String?
    var bundleId: String?
    var path: String?
    var url: String?
    var command: String?
    var zone: Double?
}

/// The whole config.json. Unbound corners are absent from `corners` and written as null.
struct ConfigFile: Codable, Equatable {
    var zone: Double
    var corners: [Corner: CornerAction]

    static let `default` = ConfigFile(zone: Config.defaultZone, corners: [
        .topRight: CornerAction(type: "keystroke", keys: "ctrl+shift+cmd+4"),
        .topLeft: CornerAction(type: "app", bundleId: "com.google.Chrome"),
    ])

    init(zone: Double, corners: [Corner: CornerAction]) {
        self.zone = zone
        self.corners = corners
    }

    private enum CodingKeys: String, CodingKey { case zone, corners }

    private struct CornerKey: CodingKey {
        let stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zone = try container.decodeIfPresent(Double.self, forKey: .zone) ?? Config.defaultZone
        let raw = try container.decodeIfPresent([String: CornerAction?].self, forKey: .corners) ?? [:]
        var corners: [Corner: CornerAction] = [:]
        for (name, action) in raw {
            guard let corner = Corner(rawValue: name) else {
                throw ConfigError(description: "unknown corner \"\(name)\"")
            }
            corners[corner] = action
        }
        self.corners = corners
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(zone, forKey: .zone)
        var nested = container.nestedContainer(keyedBy: CornerKey.self, forKey: .corners)
        for corner in Corner.allCases {
            let key = CornerKey(stringValue: corner.rawValue)!
            if let action = corners[corner] {
                try nested.encode(action, forKey: key)
            } else {
                try nested.encodeNil(forKey: key)
            }
        }
    }
}

enum Config {
    static let defaultZone = 0.12

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/sml-corners/config.json")

    static func createIfMissing() throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try write(.default)
    }

    static func read() throws -> ConfigFile {
        do {
            let file = try JSONDecoder().decode(ConfigFile.self, from: Data(contentsOf: url))
            guard file.zone > 0, file.zone <= 0.5 else {
                throw ConfigError(description: "zone must be between 0 and 0.5")
            }
            return file
        } catch let error as DecodingError {
            throw ConfigError(description: describe(error))
        }
    }

    static func write(_ file: ConfigFile) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(file)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }

    static func openInEditor() {
        try? createIfMissing()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-t", url.path]
        try? process.run()
    }

    /// Converts the file into runnable bindings. Incomplete or invalid corners are skipped and reported.
    static func bindings(from file: ConfigFile) -> (bindings: [Corner: CornerBinding], errors: [String]) {
        var bindings: [Corner: CornerBinding] = [:]
        var errors: [String] = []
        for (corner, action) in file.corners {
            let zone = action.zone ?? file.zone
            do {
                guard zone > 0, zone <= 0.5 else {
                    throw ConfigError(description: "zone must be between 0 and 0.5")
                }
                bindings[corner] = CornerBinding(zone: zone, action: try self.action(from: action))
            } catch {
                errors.append("\(corner.rawValue): \(error)")
            }
        }
        return (bindings, errors)
    }

    static func action(from a: CornerAction) throws -> ActionKind {
        func nonEmpty(_ s: String?) -> String? {
            guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }
        switch a.type {
        case "keystroke":
            guard let keys = nonEmpty(a.keys) else {
                throw ConfigError(description: "keystroke needs \"keys\"")
            }
            guard let (code, flags) = Keys.parse(keys) else {
                throw ConfigError(description: "cannot parse keys \"\(keys)\"")
            }
            return .keystroke(code, flags)
        case "app":
            let bundleId = nonEmpty(a.bundleId), path = nonEmpty(a.path)
            guard bundleId != nil || path != nil else {
                throw ConfigError(description: "app needs \"bundleId\" or \"path\"")
            }
            return .app(bundleId: bundleId, path: path)
        case "url":
            guard let text = nonEmpty(a.url) else {
                throw ConfigError(description: "url needs \"url\"")
            }
            guard let url = URL(string: text.contains("://") ? text : "https://" + text) else {
                throw ConfigError(description: "invalid url \"\(text)\"")
            }
            return .url(url)
        case "shell":
            guard let command = nonEmpty(a.command) else {
                throw ConfigError(description: "shell needs \"command\"")
            }
            return .shell(command)
        default:
            throw ConfigError(description: "unknown type \"\(a.type)\"")
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let c): return "invalid JSON: \(c.debugDescription)"
        case .keyNotFound(let k, _): return "missing \"\(k.stringValue)\""
        case .typeMismatch(_, let c), .valueNotFound(_, let c):
            return "bad value at \(c.codingPath.map(\.stringValue).joined(separator: "."))"
        @unknown default: return "invalid config"
        }
    }
}

enum Keys {
    private static let modifiers: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand,
        "ctrl": .maskControl, "control": .maskControl,
        "shift": .maskShift,
        "alt": .maskAlternate, "opt": .maskAlternate, "option": .maskAlternate,
        "fn": .maskSecondaryFn,
    ]

    private static let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50,
        "delete": 51, "escape": 53, "esc": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]

    /// Key code -> canonical name (the longer spelling wins, e.g. "escape" over "esc").
    static let names: [CGKeyCode: String] = Dictionary(
        codes.map { ($0.value, $0.key) }, uniquingKeysWith: { $0.count >= $1.count ? $0 : $1 })

    private static let symbols: [String: String] = [
        "return": "↩", "tab": "⇥", "space": "Space", "delete": "⌫", "escape": "⎋",
        "left": "←", "right": "→", "down": "↓", "up": "↑",
    ]

    /// Parses e.g. "ctrl+shift+cmd+4".
    static func parse(_ string: String) -> (CGKeyCode, CGEventFlags)? {
        var flags: CGEventFlags = []
        var code: CGKeyCode?
        for part in string.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if let m = modifiers[part] {
                flags.insert(m)
            } else if let c = codes[part], code == nil {
                code = c
            } else {
                return nil
            }
        }
        return code.map { ($0, flags) }
    }

    /// Builds the config string for a pressed key, e.g. "ctrl+shift+cmd+4".
    static func string(code: CGKeyCode, modifiers: NSEvent.ModifierFlags) -> String? {
        guard let name = names[code] else { return nil }
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("alt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        return (parts + [name]).joined(separator: "+")
    }

    /// Human-readable form, e.g. "⌃⇧⌘4".
    static func display(_ keys: String) -> String? {
        guard let (code, flags) = parse(keys), let name = names[code] else { return nil }
        var text = flags.contains(.maskSecondaryFn) ? "fn " : ""
        if flags.contains(.maskControl) { text += "⌃" }
        if flags.contains(.maskAlternate) { text += "⌥" }
        if flags.contains(.maskShift) { text += "⇧" }
        if flags.contains(.maskCommand) { text += "⌘" }
        return text + (symbols[name] ?? name.uppercased())
    }

    static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a = a.flatMap(parse), let b = b.flatMap(parse) else { return false }
        return a.0 == b.0 && a.1 == b.1
    }
}
