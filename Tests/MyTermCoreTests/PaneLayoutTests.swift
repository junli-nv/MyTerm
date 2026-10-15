import Foundation
import MyTermCore

func checkPaneLayouts() throws {
    let a = UUID(), b = UUID(), c = UUID()
    let first = PaneLayout.leaf(a).inserting(b, beside: a, axis: .vertical)
    let tree = first.inserting(c, beside: b, axis: .horizontal)
    checkEqual(tree.leaves, [a, b, c])
    checkEqual(tree.removing(b)?.leaves, [a, c])
    checkEqual(tree.removing(a)?.removing(c), .leaf(b))
    checkEqual(tree.removing(a)?.removing(b)?.removing(c), nil)
    checkEqual(tree.removing(UUID()), tree)
    checkEqual(tree.inserting(UUID(), beside: UUID(), axis: .vertical), tree)
    let mapped = [a: UUID(), b: UUID(), c: UUID()]
    checkEqual(tree.remapping(mapped)?.leaves, [mapped[a]!, mapped[b]!, mapped[c]!])
    checkEqual(tree.remapping([a: UUID()]), nil)
    var saved = SavedSession(name: "Split", tabs: [SessionTab(), SessionTab(), SessionTab()], selectedIndex: 1)
    saved.paneSessionIDs = [a, b, c]; saved.paneLayouts = [tree]
    try saved.validateLayouts()
    let restored = try JSONDecoder().decode(SavedSession.self, from: JSONEncoder().encode(saved))
    checkEqual(restored, saved)
    var invalid = saved; invalid.paneLayouts = [first]
    checkThrows(try invalid.validateLayouts())
    invalid = saved; invalid.paneSessionIDs = [a, b, b]
    checkThrows(try invalid.validateLayouts())
    // Legacy archives need neither UUID maps nor layout metadata.
    let legacy = SavedSession(name: "Old", tabs: [SessionTab()], selectedIndex: 0)
    try JSONDecoder().decode(SavedSession.self, from: JSONEncoder().encode(legacy)).validateLayouts()
    var shortcuts = SplitShortcuts(); try shortcuts.validate()
    checkEqual(shortcuts.horizontal.key, "h"); checkEqual(shortcuts.vertical.key, "v")
    shortcuts.vertical = shortcuts.horizontal; checkThrows(try shortcuts.validate())
    shortcuts = SplitShortcuts(); shortcuts.horizontal.key = "s"; checkThrows(try shortcuts.validate())
    shortcuts.horizontal = SplitKeyBinding(key: "v", shift: false); checkThrows(try shortcuts.validate())
    shortcuts.horizontal = SplitKeyBinding(key: "h", shift: false, option: true); checkThrows(try shortcuts.validate())
    shortcuts.horizontal = SplitKeyBinding(key: "j", control: true); try shortcuts.validate()
    checkEqual(try JSONDecoder().decode(SplitShortcuts.self, from: JSONEncoder().encode(shortcuts)), shortcuts)
}
