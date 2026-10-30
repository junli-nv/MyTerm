import Foundation
import MyTermCore

/// The GUI suite exercises loading/failure/cancellation against an isolated adapter.
enum CodexClusterRefreshCheck {
    static func run(root: URL, bridge: CodexBridge) throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid("Cluster refresh: " + message) }
        }
        let directory = root.appendingPathComponent("refresh-check")
        let index = directory.appendingPathComponent("codex-clusters.json")
        var catalog = CodexClusterCatalog()
        let cluster = try catalog.ensureDefaultCluster()
        let thread = UUID().uuidString
        let opened = Date(timeIntervalSince1970: 100)
        catalog.conversations.append(.init(id: thread, clusterID: cluster.id, title: "Cached title", lastOpened: opened))
        try catalog.save(to: index)
        let model = CodexClusterModel(root: directory)
        let originalPath = model.directory(for: cluster.id)
        model.renameCluster(cluster.id, name: "Renamed default")
        try require(model.defaultCluster() == cluster.id && model.directory(for: cluster.id) == originalPath,
                    "Renaming the default changed its identity or directory")
        try require(model.checks.isEmpty, "Initial status must be unchecked")
        let executable = bridge.connection.executable
        defer { bridge.connection.executable = executable }
        bridge.connection.executable = "/usr/bin/false"
        model.refresh(clusterID: cluster.id, bridge: bridge)
        try require(model.busy, "Refresh did not publish loading state: " + model.message)
        let deadline = Date().addingTimeInterval(5)
        while model.busy && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        try require(!model.busy, "Failed adapter left UI busy")
        guard case .unverified = model.checks[thread] else {
            throw ConfigurationError.invalid("Failed adapter must leave conversation unverified")
        }
        let saved = try CodexClusterCatalog.load(from: index)
        try require(saved.conversations == catalog.conversations, "Failure altered history index or opening date")
        let adapter = root.appendingPathComponent("metadata-adapter")
        let response = try JSONSerialization.data(withJSONObject: ["id": 2, "result": ["thread": [
            "id": thread, "cwd": originalPath!.path, "name": "Updated title"
        ]]])
        let quoted = "'" + String(decoding: response, as: UTF8.self).replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = """
        #!/bin/bash
        while IFS= read -r line; do
          case "$line" in
            *'"method":"initialize"'*) printf '%s\\n' '{"id":1,"result":{}}' ;;
            *'thread'*'read'*) printf '%s\\n' \(quoted) ;;
            *'"method":"initialized"'*) ;;
            *) exit 7 ;;
          esac
        done
        """
        try script.write(to: adapter, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: adapter.path)
        bridge.connection.executable = adapter.path
        model.refresh(clusterID: cluster.id, bridge: bridge)
        try require(model.busy && model.checks[thread] == nil, "Retry must clear stale status while loading")
        let retryDeadline = Date().addingTimeInterval(5)
        while model.busy && Date() < retryDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        try require(!model.busy && model.checks[thread] == .available(name: "Updated title"),
                    "Metadata retry failed: " + String(describing: model.checks[thread]))
        let refreshed = try CodexClusterCatalog.load(from: index)
        try require(refreshed.conversations.first?.title == "Updated title" && refreshed.conversations.first?.lastOpened == opened,
                    "Refresh failed to persist the new title or changed the opening date")
        let cancelled = CodexClusterModel(root: directory)
        cancelled.cancelLaunch()
        cancelled.refresh(clusterID: cluster.id, bridge: bridge)
        try require(!cancelled.busy && cancelled.checks.isEmpty, "Cancelled chooser started refresh")
        print("PASS: cluster identity; metadata failure/retry; title persistence without date changes; loading and cancellation")
    }
}
