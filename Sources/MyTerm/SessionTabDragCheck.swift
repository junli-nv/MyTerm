import AppKit
import MyTermCore

/// Exercise the same asynchronous item-provider path used by native tab drops.
enum SessionTabDragCheck {
    static func run(workspace: Workspace) throws {
        let original = workspace.sessions
        let selected = workspace.selectedID
        defer { workspace.sessions = original; workspace.selectedID = selected }
        guard original.count >= 2 else { throw ConfigurationError.invalid("Tab drag check needs two sessions") }
        let left = original[0], right = original[1]
        workspace.sessions = [left, right]
        workspace.selectedID = left.id

        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid(message) }
        }
        func drop(_ provider: NSItemProvider, on target: UUID, expected: Bool) throws {
            var result: Bool?
            let accepted = SessionTabDrag.receive([provider], workspace: workspace, targetID: target) { result = $0 }
            try require(accepted, "Tab provider was not accepted")
            let deadline = Date().addingTimeInterval(2)
            while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            try require(result == expected, "Tab drop result \(String(describing: result)), expected \(expected)")
        }
        try drop(SessionTabDrag(id: right.id).itemProvider, on: left.id, expected: true)
        try require(workspace.sessions.map(\.id) == [right.id, left.id], "Right-to-left tab move failed")
        try require(workspace.selectedID == left.id && workspace.sessions[1] === left, "Tab move replaced the selected terminal")
        try drop(SessionTabDrag(id: right.id).itemProvider, on: left.id, expected: true)
        try require(workspace.sessions.map(\.id) == [left.id, right.id], "Left-to-right tab move failed")
        try drop(SessionTabDrag(id: left.id).itemProvider, on: left.id, expected: true)
        try drop(SessionTabDrag(id: UUID()).itemProvider, on: left.id, expected: false)
        try drop(SessionTabDrag(id: left.id).itemProvider, on: UUID(), expected: false)
        let malformed = NSItemProvider()
        malformed.registerDataRepresentation(forTypeIdentifier: SessionTabDrag.typeIdentifier, visibility: .ownProcess) { completion in
            completion(Data("not-a-uuid".utf8), nil); return nil
        }
        try drop(malformed, on: left.id, expected: false)
        try require(!SessionTabDrag.receive([NSItemProvider(object: "unrelated text" as NSString)], workspace: workspace, targetID: left.id), "Text drag accepted as terminal tab")
        try require(workspace.sessions.map(\.id) == [left.id, right.id], "Invalid drop changed order")
        workspace.selectAdjacentTab(1)
        try require(workspace.selectedID == right.id, "Keyboard navigation ignored reordered tabs")
        print("PASS: session tab drag: both directions, stable identity/selection, same-tab, closed tabs, malformed/unrelated providers and keyboard navigation")
    }
}
