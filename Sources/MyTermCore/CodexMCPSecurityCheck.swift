import Foundation
import Darwin

/// Read-only security observations, not a claim that every TCC permission is granted.
public enum CodexMCPSecurityCheck {
    public struct Report: Codable {
        public let checkedAt: Date
        public let executableExists: Bool
        public let executableAllowed: Bool
        public let quarantine: Bool
        public let signatureExit: Int32?
        public let gatekeeperExit: Int32?
    }
    public static func run(executable: URL) -> Report {
        let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let quarantine = [app.path, executable.path].contains { getxattr($0, "com.apple.quarantine", nil, 0, 0, 0) >= 0 }
        return Report(checkedAt: Date(), executableExists: FileManager.default.fileExists(atPath: executable.path),
            executableAllowed: access(executable.path, X_OK) == 0, quarantine: quarantine,
            signatureExit: assess("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]),
            gatekeeperExit: assess("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path]))
    }
    // Output is deliberately discarded: system messages may contain user paths.
    private static func assess(_ command: String, _ arguments: [String]) -> Int32? {
        let process = Process(); process.executableURL = URL(fileURLWithPath: command); process.arguments = arguments
        process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(4)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        guard !process.isRunning else { kill(process.processIdentifier, SIGKILL); return nil }
        return process.terminationStatus
    }
}
