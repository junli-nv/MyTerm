import Foundation

public enum DragUploadProtocol: String, Codable, CaseIterable {
    case automatic, trzsz, zmodem
}

public enum TrzszIntegration {
    public static func arguments(sshArguments: [String]) -> [String] {
        ["--dragfile", "/usr/bin/ssh"] + sshArguments
    }
    /// The upstream drag detector accepts shell-quoted absolute paths terminated by a space.
    public static func dragInput(_ urls: [URL]) throws -> Data {
        guard !urls.isEmpty else { throw ConfigurationError.invalid("请选择上传文件。") }
        let paths = try urls.map { url -> String in
            guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path),
                  !url.path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw ConfigurationError.invalid("上传路径必须可读，且不能包含控制字符。")
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            guard values.isRegularFile == true || values.isDirectory == true else {
                throw ConfigurationError.invalid("trzsz 仅支持普通文件和目录。")
            }
            return "'" + url.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return Data((paths.joined(separator: " ") + " ").utf8)
    }
}
