import Foundation

extension SFTPClient {
    /// Directory retries merge folders and skip only byte-identical completed files.
    /// Links and special files are rejected rather than followed outside the selected tree.
    public func uploadItem(_ source: URL, to remote: String,
                           progress: (String, UInt64, UInt64) -> Void) throws {
        var count = 0
        func visit(_ local: URL, _ target: String, depth: Int) throws {
            count += 1
            guard depth <= 128, count <= 100_000 else { throw SFTPError(code: 4, message: "目录层级或文件数量超出限制。") }
            let values = try local.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw SFTPError(code: 4, message: "递归传输不跟随符号链接：" + local.path) }
            if values.isDirectory == true {
                try createDirectory(target)
                for child in try FileManager.default.contentsOfDirectory(at: local, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    try visit(child, SFTPClient.joining(target, child.lastPathComponent), depth: depth + 1)
                }
            } else if values.isRegularFile == true {
                if try attributes(at: target) != nil, try contentsMatch(local, remote: target) {
                    let size = UInt64(max(0, values.fileSize ?? 0)); progress(local.path, size, size)
                } else {
                    try upload(local, to: target) { progress(local.path, $0, $1) }
                }
            } else { throw SFTPError(code: 4, message: "不支持此文件类型：" + local.path) }
        }
        try visit(source, remote, depth: 0)
    }

    /// Uses the existing per-file resume metadata. Never writes through local symlinks.
    public func downloadItem(_ remote: String, to destination: URL,
                             progress: (String, UInt64, UInt64) -> Void) throws {
        var count = 0
        func visit(_ source: String, _ local: URL, depth: Int) throws {
            count += 1
            guard depth <= 128, count <= 100_000 else { throw SFTPError(code: 4, message: "目录层级或文件数量超出限制。") }
            guard let entry = try attributes(at: source), !entry.isLink else {
                throw SFTPError(code: 4, message: "文件不存在或是符号链接：" + source)
            }
            // resourceValues detects a dangling symlink too; fileExists alone does not.
            let existing = try? local.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard existing?.isSymbolicLink != true else { throw SFTPError(code: 4, message: "目标是符号链接：" + local.path) }
            if entry.isDirectory {
                if FileManager.default.fileExists(atPath: local.path), existing?.isDirectory != true {
                    throw SFTPError(code: 4, message: "目标不是普通目录：" + local.path)
                }
                if !FileManager.default.fileExists(atPath: local.path) {
                    try FileManager.default.createDirectory(at: local, withIntermediateDirectories: false)
                }
                for child in try list(source) {
                    try visit(SFTPClient.joining(source, child.name), local.appendingPathComponent(child.name), depth: depth + 1)
                }
            } else {
                guard entry.permissions.map({ $0 & 0o170000 == 0o100000 }) ?? true else {
                    throw SFTPError(code: 4, message: "不支持此文件类型：" + source)
                }
                if FileManager.default.fileExists(atPath: local.path), try contentsMatch(local, remote: source) {
                    progress(source, entry.size ?? 0, entry.size ?? 0)
                } else { try download(source, to: local) { progress(source, $0, $1) } }
            }
        }
        try visit(remote, destination, depth: 0)
    }
}
