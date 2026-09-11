import Foundation
import CZlib

enum HistoryCompression {
    static let expandedLimit = 256 * 1024 * 1024
    static func transform(_ data: Data, compress: Bool) throws -> Data {
        guard data.count <= expandedLimit else { throw ConfigurationError.invalid("历史文件解压后不能超过 256 MiB。") }
        var stream = z_stream()
        let status = compress
            ? deflateInit2_(&stream, Z_BEST_SPEED, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            : inflateInit2_(&stream, 15 + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw ConfigurationError.invalid("无法初始化日志压缩。") }
        defer { if compress { deflateEnd(&stream) } else { inflateEnd(&stream) } }
        return try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(data.count)
            var result = Data(), chunk = [UInt8](repeating: 0, count: 65536)
            while true {
                let code = chunk.withUnsafeMutableBytes { output -> Int32 in
                    stream.next_out = output.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(output.count)
                    return compress ? deflate(&stream, Z_FINISH) : inflate(&stream, Z_NO_FLUSH)
                }
                guard code == Z_OK || code == Z_STREAM_END else { throw ConfigurationError.invalid("日志压缩数据损坏或不完整。") }
                let count = chunk.count - Int(stream.avail_out)
                guard result.count + count <= expandedLimit else { throw ConfigurationError.invalid("历史文件解压后不能超过 256 MiB。") }
                result.append(contentsOf: chunk.prefix(count))
                if code == Z_STREAM_END {
                    guard stream.avail_in == 0 else { throw ConfigurationError.invalid("日志包含多余压缩数据。") }
                    return result
                }
                if count == 0 && stream.avail_in == 0 { throw ConfigurationError.invalid("日志压缩数据不完整。") }
            }
        }
    }
}
