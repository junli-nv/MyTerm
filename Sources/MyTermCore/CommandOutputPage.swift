import Foundation

/// Byte offsets stay authoritative even for malformed remote output. Only a
/// valid, incomplete UTF-8 prefix may defer the end of a page; arbitrary runs
/// of continuation bytes must never prevent forward progress.
enum CommandOutputPage {
    static func end(in bytes: Data, from offset: Int, limit: Int, running: Bool) -> Int {
        let end = min(bytes.count, offset + limit)
        guard end > offset, end < bytes.count || running else { return end }
        var lead = end - 1
        while lead > offset, end - lead < 4, bytes[lead] & 0xc0 == 0x80 { lead -= 1 }
        let length: Int
        switch bytes[lead] {
        case 0xc2...0xdf: length = 2
        case 0xe0...0xef: length = 3
        case 0xf0...0xf4: length = 4
        default: return end
        }
        guard end - lead < length else { return end }
        let availableEnd = min(bytes.count, lead + length)
        let prefix = Array(bytes[lead..<availableEnd])
        guard prefix.dropFirst().allSatisfy({ $0 & 0xc0 == 0x80 }) else { return end }
        if prefix.count > 1 {
            // Reject overlong encodings, surrogate codepoints and values above U+10FFFF.
            switch prefix[0] {
            case 0xe0 where prefix[1] < 0xa0: return end
            case 0xed where prefix[1] > 0x9f: return end
            case 0xf0 where prefix[1] < 0x90: return end
            case 0xf4 where prefix[1] > 0x8f: return end
            default: break
            }
        }
        return prefix.count == length || running ? lead : end
    }
}
