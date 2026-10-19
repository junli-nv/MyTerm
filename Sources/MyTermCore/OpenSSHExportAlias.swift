import Foundation

/// Names are labels, never OpenSSH patterns. Keep generated aliases ASCII and bounded.
enum OpenSSHExportAlias {
    static func slug(_ name: String, fallback: String = "host") -> String {
        let ascii = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        let value = name.lowercased().unicodeScalars.map { ascii.contains($0) ? String($0) : "-" }
            .joined().split(separator: "-").joined(separator: "-")
        return value.isEmpty ? fallback : String(value.prefix(40))
    }
}
