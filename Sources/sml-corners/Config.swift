import CoreGraphics
import Foundation

enum Corner: String, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

/// What a corner does. Add a case here (and in `Binding.init`) to add an action type.
enum ActionKind {
    case keystroke(CGKeyCode, CGEventFlags)
    case app(bundleId: String?, path: String?)
    case shell(String)
}

struct Binding {
    let zone: Double
    let action: ActionKind
}

struct ConfigError: Error, CustomStringConvertible {
    let description: String
}

private struct RawAction: Decodable {
    var type: String
    var keys: String?
    var bundleId: String?
    var path: String?
    var command: String?
    var zone: Double?
}

private struct RawConfig: Decodable {
    var zone: Double?
    var corners: [String: RawAction?]
}

enum Config {
    static let defaultZone = 0.12

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/sml-corners/config.json")

    static let defaultContents = """
    {
      "zone": 0.12,
      "corners": {
        "topRight": { "type": "keystroke", "keys": "ctrl+shift+cmd+4" },
        "topLeft": { "type": "app", "bundleId": "com.google.Chrome" },
        "bottomLeft": null,
        "bottomRight": null
      }
    }

    """

    static func createIfMissing() throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try defaultContents.write(to: url, atomically: true, encoding: .utf8)
    }

    static func load() throws -> [Corner: Binding] {
        let raw: RawConfig
        do {
            raw = try JSONDecoder().decode(RawConfig.self, from: Data(contentsOf: url))
        } catch let error as DecodingError {
            throw ConfigError(description: describe(error))
        }
        var result: [Corner: Binding] = [:]
        for (name, action) in raw.corners {
            guard let corner = Corner(rawValue: name) else {
                throw ConfigError(description: "unknown corner \"\(name)\"")
            }
            guard let action else { continue }
            let zone = action.zone ?? raw.zone ?? defaultZone
            guard zone > 0, zone <= 0.5 else {
                throw ConfigError(description: "\(name): zone must be between 0 and 0.5")
            }
            result[corner] = Binding(zone: zone, action: try parse(action, name))
        }
        return result
    }

    private static func parse(_ a: RawAction, _ name: String) throws -> ActionKind {
        switch a.type {
        case "keystroke":
            guard let keys = a.keys else {
                throw ConfigError(description: "\(name): keystroke needs \"keys\"")
            }
            guard let (code, flags) = Keys.parse(keys) else {
                throw ConfigError(description: "\(name): cannot parse keys \"\(keys)\"")
            }
            return .keystroke(code, flags)
        case "app":
            guard a.bundleId != nil || a.path != nil else {
                throw ConfigError(description: "\(name): app needs \"bundleId\" or \"path\"")
            }
            return .app(bundleId: a.bundleId, path: a.path)
        case "shell":
            guard let command = a.command else {
                throw ConfigError(description: "\(name): shell needs \"command\"")
            }
            return .shell(command)
        default:
            throw ConfigError(description: "\(name): unknown type \"\(a.type)\"")
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
}
