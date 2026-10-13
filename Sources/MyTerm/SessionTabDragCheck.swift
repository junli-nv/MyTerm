import AppKit
import MyTermCore

/// Exercise the production native pasteboard format and session mutations.
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
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        func drop(_ item: NSPasteboardItem, on target: UUID, expected: Bool) throws {
            pasteboard.clearContents(); pasteboard.writeObjects([item])
            let result = SessionTabDrag.decode(pasteboard).map { workspace.moveSessionTab($0, to: target) } ?? false
            try require(result == expected, "Native tab drop result differs from expected")
        }
        try drop(SessionTabDrag(id: right.id).pasteboardItem, on: left.id, expected: true)
        try require(workspace.sessions.map(\.id) == [right.id, left.id], "Right-to-left tab move failed")
        try require(workspace.selectedID == left.id && workspace.sessions[1] === left, "Tab move replaced the selected terminal")
        try drop(SessionTabDrag(id: right.id).pasteboardItem, on: left.id, expected: true)
        try require(workspace.sessions.map(\.id) == [left.id, right.id], "Left-to-right tab move failed")
        try drop(SessionTabDrag(id: left.id).pasteboardItem, on: left.id, expected: true)
        try drop(SessionTabDrag(id: UUID()).pasteboardItem, on: left.id, expected: false)
        try drop(SessionTabDrag(id: left.id).pasteboardItem, on: UUID(), expected: false)
        let malformed = NSPasteboardItem()
        malformed.setString("not-a-uuid", forType: SessionTabDrag.pasteboardType)
        try drop(malformed, on: left.id, expected: false)
        let unrelated = NSPasteboardItem(); unrelated.setString("text", forType: .string)
        try drop(unrelated, on: left.id, expected: false)
        pasteboard.clearContents(); pasteboard.writeObjects([SessionTabDrag(id: left.id).pasteboardItem, SessionTabDrag(id: right.id).pasteboardItem])
        try require(SessionTabDrag.decode(pasteboard) == nil, "Multiple tab payload accepted")
        try require(workspace.sessions.map(\.id) == [left.id, right.id], "Invalid drop changed order")
        workspace.selectAdjacentTab(1)
        try require(workspace.selectedID == right.id, "Keyboard navigation ignored reordered tabs")
        print("PASS: session tab drag: both directions, stable identity/selection, same-tab, closed tabs, malformed/unrelated native payloads and keyboard navigation")
    }
}
