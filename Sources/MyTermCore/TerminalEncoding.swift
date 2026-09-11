import Foundation
import CIconv
import Darwin

public enum TerminalEncoding: String, Codable, CaseIterable {
    case utf8 = "UTF-8", gb2312 = "GB2312", gbk = "GBK", gb18030 = "GB18030", big5 = "BIG5"
    case shiftJIS = "SHIFT_JIS", eucKR = "EUC-KR", latin1 = "ISO-8859-1"
}

/// Stateful byte conversion preserves characters split between PTY reads.
public final class TerminalTranscoder {
    private let converter: iconv_t
    private var pending: [UInt8] = []
    private let replacement: [UInt8]
    public init(from: TerminalEncoding, to: TerminalEncoding) throws {
        converter = iconv_open(to.rawValue, from.rawValue)
        guard myterm_iconv_invalid(converter) == 0 else { throw ConfigurationError.invalid("系统不支持此字符编码。") }
        replacement = to == .utf8 ? Array("�".utf8) : [63]
    }
    deinit { iconv_close(converter) }
    public func convert(_ bytes: [UInt8]) -> [UInt8] {
        pending.append(contentsOf: bytes)
        var result: [UInt8] = [], offset = 0
        while offset < pending.count {
            var inputLeft = pending.count - offset
            var output = [UInt8](repeating: 0, count: max(256, inputLeft * 4 + 16))
            var outputLeft = output.count
            let code = pending.withUnsafeMutableBytes { input in
                output.withUnsafeMutableBytes { out in
                    myterm_convert(converter, input.baseAddress!.advanced(by: offset).assumingMemoryBound(to: CChar.self), &inputLeft,
                        out.baseAddress!.assumingMemoryBound(to: CChar.self), &outputLeft)
                }
            }
            offset = pending.count - inputLeft
            result.append(contentsOf: output.prefix(output.count - outputLeft))
            if code == EINVAL { break }
            if code == EILSEQ { result.append(contentsOf: replacement); offset += 1 }
            else if code != 0 && code != E2BIG { result.append(contentsOf: replacement); offset = pending.count }
        }
        pending.removeFirst(offset)
        return result
    }
}
