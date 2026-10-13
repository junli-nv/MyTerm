import SwiftUI

extension Workspace {
    /// Move to the target's current position: leftward before it, rightward after it.
    /// Keep the same session objects and selected UUID; never reconnect a terminal.
    @discardableResult
    func moveSessionTab(_ id: UUID, to targetID: UUID) -> Bool {
        guard let source = sessions.firstIndex(where: { $0.id == id }),
              let destination = sessions.firstIndex(where: { $0.id == targetID }) else { return false }
        guard source != destination else { return true }
        var reordered = sessions
        reordered.insert(reordered.remove(at: source), at: destination)
        sessions = reordered
        return true
    }
}

/// Only typed, single-tab payloads are accepted. Terminal files and sidebar
/// server drags use different types and cannot reorder the tab strip.
struct SessionTabDrag {
    static let typeIdentifier = "local.myterm.session-tab"
    static let pasteboardType = NSPasteboard.PasteboardType(typeIdentifier)
    let id: UUID

    var pasteboardItem: NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setData(Data(id.uuidString.utf8), forType: Self.pasteboardType)
        return item
    }
    static func decode(_ pasteboard: NSPasteboard) -> UUID? {
        guard let items = pasteboard.pasteboardItems, items.count == 1,
              let data = items[0].data(forType: pasteboardType),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return UUID(uuidString: text)
    }
}
