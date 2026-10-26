import AppKit
import MyTermCore

/// Verify the exported artifact, not just the in-memory encoder.
enum TerminalDiagnosticsCheck {
    static func run(workspace: Workspace) throws {
        let model = TerminalDiagnostics.shared
        defer { model.log.clear() }
        model.log.start()
        model.log.record(.marker)
        let data = try model.report(workspace: workspace)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        guard object["schema"] as? Int == 2, object["mcp"] is [String: Any], let trace = object["trace"] as? [String: Any],
              (trace["entries"] as? [Any])?.count == 2 else {
            throw ConfigurationError.invalid("Diagnostic report schema or events invalid")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-diagnostics-check-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appendingPathComponent("report.zip"), extracted = root.appendingPathComponent("extracted")
        try TerminalDiagnostics.archive(data, to: zip)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, extracted.path]
        try process.run(); process.waitUntilExit()
        let contents = extracted.appendingPathComponent("MyTerm-Diagnostics")
        let names = try FileManager.default.contentsOfDirectory(atPath: contents.path).sorted()
        guard process.terminationStatus == 0, names == ["README.txt", "diagnostic.json"],
              try Data(contentsOf: contents.appendingPathComponent("diagnostic.json")) == data else {
            throw ConfigurationError.invalid("Diagnostic archive content mismatch")
        }
        print("PASS: metadata diagnostic report and ZIP export round trip with exactly two expected files")
    }
}
