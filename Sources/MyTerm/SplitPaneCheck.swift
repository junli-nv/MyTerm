import AppKit
import SwiftUI
import MyTermCore

private struct SplitCheckRoot: View {
    @ObservedObject var workspace: Workspace
    var body: some View {
        if let selected = workspace.selected { SplitPaneView(workspace: workspace, layout: workspace.layout(containing: selected.id)) }
    }
}

enum SplitPaneCheck {
    static func run() throws {
        try directSplits()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-split-check-\(UUID())")
        let workspace = Workspace(applicationSupportDirectory: directory)
        let window = NSWindow(contentRect: NSRect(x: 50, y: 60, width: 1000, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { workspace.stopAll(); window.close(); try? FileManager.default.removeItem(at: directory) }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid("Split panes: " + message) }
        }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)); window.contentView?.layoutSubtreeIfNeeded() }
        workspace.newLocal(); let a = workspace.selected!
        workspace.newLocal(); let b = workspace.selected!
        workspace.newLocal(); let c = workspace.selected!
        let terminals = [a.terminal, b.terminal, c.terminal]
        try require(workspace.moveToSplit(b.id, beside: a.id, axis: .vertical), "Cannot create left/right split")
        workspace.selectTab(a)
        window.contentView = NSHostingView(rootView: SplitCheckRoot(workspace: workspace))
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); settle(); settle()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func splits() -> [PaneSplitView] { descendants(window.contentView!).compactMap { $0 as? PaneSplitView } }
        func equalHalves(_ split: PaneSplitView) -> Bool {
            let sizes = split.arrangedSubviews.map { split.isVertical ? $0.frame.width : $0.frame.height }
            return sizes.count == 2 && abs(sizes[0] - sizes[1]) <= 1
        }
        guard let outer = splits().first else { throw ConfigurationError.invalid("Missing initial splitter") }
        try require(equalHalves(outer), "Initial left/right panes are not equal")
        let originalLeft = outer.arrangedSubviews[0].frame
        try require(workspace.moveToSplit(c.id, beside: b.id, axis: .horizontal), "Cannot nest top/bottom split")
        settle(); settle()
        try require(outer.arrangedSubviews[0].frame == originalLeft, "Nesting changed an unrelated pane")
        try require(splits().count == 2 && splits().allSatisfy(equalHalves), "Mixed splits are not equal halves")
        try require(workspace.visibleTabs.map(\.id) == [a.id] && workspace.layout(containing: a.id).leaves == [a.id, b.id, c.id], "Split duplicated tab membership")
        try require(terminals.allSatisfy { $0.window === window }, "Not all terminals mounted")
        let sizeDeadline = Date().addingTimeInterval(4)
        while Date() < sizeDeadline && terminals.contains(where: {
            guard let scroll = $0.enclosingScrollView else { return true }
            return abs($0.bounds.width - scroll.contentSize.width) > 2 || abs($0.bounds.height - scroll.contentSize.height) > 2
        }) { settle() }
        let rects = terminals.map { $0.convert($0.bounds, to: nil) }
        try require(rects[0].maxX <= rects[1].minX + 4 && abs(rects[1].minX - rects[2].minX) < 4, "Left/right orientation wrong: \(rects)")
        try require(rects[1].minY >= rects[2].maxY - 4, "Top/bottom orientation wrong: \(rects)")
        let pids = terminals.map { $0.process.shellPid }
        let dividers = descendants(window.contentView!).compactMap { $0 as? NSSplitView }.filter { $0.arrangedSubviews.count == 2 && $0.bounds.width > 900 }
        if let divider = dividers.first {
            divider.setPosition(380, ofDividerAt: 0); settle()
            try require(a.terminal.bounds.width < rects[0].width - 30, "Divider adjustment did not resize terminal")
        } else { throw ConfigurationError.invalid("Missing draggable split divider") }
        let manuallySizedLeft = outer.arrangedSubviews[0].frame
        workspace.newLocal(); let d = workspace.selected!
        workspace.moveToSplit(d.id, beside: a.id, axis: .horizontal); settle(); settle()
        guard let resizedOuter = splits().first else { throw ConfigurationError.invalid("Missing resized splitter") }
        try require(resizedOuter.arrangedSubviews[0].frame == manuallySizedLeft, "Nesting reset manually adjusted width")
        try require(splits().filter { !$0.isVertical }.allSatisfy(equalHalves), "New top/bottom split is not equal")
        workspace.close(d); settle()
        try require(splits().first?.arrangedSubviews[0].frame == manuallySizedLeft, "Collapsing child reset parent width")
        window.setContentSize(NSSize(width: 1100, height: 740)); settle()
        try require(terminals.map { $0.process.shellPid } == pids, "Resize restarted a process")
        workspace.focusPane(a.id); workspace.focusSelectedPane(); settle()
        try require(window.firstResponder === a.terminal && workspace.selectedID == a.id, "Active pane focus lost: selected=\(String(describing: workspace.selectedID)), expected=\(a.id), responder=\(String(describing: window.firstResponder)), terminal=\(a.terminal), mounted=\(a.terminal.window === window)")
        // A real terminal click must change the selected session, not merely its caret.
        let point = b.terminal.convert(NSPoint(x: 30, y: 30), to: nil)
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        b.terminal.mouseDown(with: event); settle()
        try require(workspace.selectedID == b.id && window.firstResponder === b.terminal, "Mouse click did not select pane")
        var reconnects = [0, 0]
        a.terminal.reconnectHandler = { reconnects[0] += 1 }
        b.terminal.reconnectHandler = { reconnects[1] += 1 }
        window.makeFirstResponder(nil)
        let reconnect = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
            windowNumber: window.windowNumber, context: nil, characters: "r", charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15)!
        try require(!a.terminal.handleReconnectEvent(reconnect) && b.terminal.handleReconnectEvent(reconnect) && reconnects == [0, 1], "Reconnect reached an inactive pane")
        a.terminal.reconnectHandler = nil; b.terminal.reconnectHandler = nil
        workspace.newLocal(); let otherTab = workspace.selected!
        workspace.selectTab(a); settle()
        try require(workspace.selectedID == b.id, "Tab did not remember active pane")
        guard let restoredDivider = splits().first else { throw ConfigurationError.invalid("Tab lost divider") }
        let expectedWidth = (restoredDivider.bounds.width - restoredDivider.dividerThickness) * manuallySizedLeft.width / 999
        try require(abs(restoredDivider.arrangedSubviews[0].frame.width - expectedWidth) <= 2,
                    "Window resize or tab switching reset divider proportion")
        workspace.selectAdjacentTab(1)
        try require(workspace.selectedID == otherTab.id, "Tab navigation visited a hidden pane")
        workspace.selectAdjacentTab(-1)
        try require(workspace.selectedID == b.id, "Reverse tab navigation lost pane focus")
        workspace.close(otherTab)
        let snapshot = workspace.sessionSnapshot(named: "Split snapshot")
        try snapshot.validateLayouts()
        let other = Workspace(applicationSupportDirectory: directory.appendingPathComponent("restore"))
        defer { other.stopAll() }
        other.restore(snapshot)
        try require(other.sessions.count == 3 && other.visibleTabs.count == 1 && other.selected?.id == other.sessions[1].id,
                    "Restoring lost split layout or active pane")
        try require(workspace.moveToSplit(a.id, beside: c.id, axis: .vertical), "Moving within a split failed")
        try require(Set(workspace.layout(containing: c.id).leaves).count == 3, "Moving within split duplicated a pane")
        workspace.detachPane(a.id); settle()
        try require(workspace.visibleTabs.count == 2 && a.terminal === terminals[0], "Detach replaced terminal")
        workspace.close(b); settle()
        try require(workspace.visibleTabs.count == 2 && workspace.sessions.count == 2, "Closing pane lost sibling")
        workspace.moveToSplit(a.id, beside: c.id, axis: .horizontal)
        workspace.closeTab(containing: c.id)
        try require(workspace.sessions.isEmpty && workspace.paneLayouts.isEmpty && workspace.paneFocus.isEmpty && workspace.paneFractions.isEmpty, "Closing tab left pane state")
        let suite = "myterm-split-shortcuts-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = SplitShortcutPreferences(defaults: defaults)
        var shortcuts = SplitShortcuts(); shortcuts.horizontal.key = "j"
        try preferences.save(shortcuts)
        try require(SplitShortcutPreferences(defaults: defaults).value == shortcuts, "Shortcut settings did not persist")
        shortcuts.vertical = shortcuts.horizontal
        do { try preferences.save(shortcuts); throw ConfigurationError.invalid("Accepted duplicate shortcut") }
        catch { try require(preferences.value.horizontal.key == "j" && preferences.value.vertical.key == "v", "Invalid shortcut changed saved settings") }
        print("PASS: split panes: nested orientations, real terminal click/focus, stable sessions, move/detach/close, layout restoration and shortcut persistence")
    }
}

extension SplitPaneCheck {
    private static func directSplits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-direct-split-\(UUID())")
        let workspace = Workspace(applicationSupportDirectory: directory)
        defer { workspace.stopAll(); try? FileManager.default.removeItem(at: directory) }
        // No views are mounted: verify connection definitions without starting SSH.
        workspace.newLocal(directory: directory.path)
        let local = workspace.selected!
        workspace.requestSplit(.vertical)
        guard let localCopy = workspace.selected, localCopy.id != local.id,
              localCopy.executable == "/bin/bash", localCopy.directory == local.directory,
              workspace.splitRequest == nil else { throw ConfigurationError.invalid("Direct local split failed") }
        workspace.focusPane(local.id)
        workspace.requestSplit(.horizontal)
        guard let nested = workspace.selected,
              workspace.layout(containing: local.id).leaves == [local.id, nested.id, localCopy.id] else {
            throw ConfigurationError.invalid("Direct nested split targeted the wrong pane")
        }
        try directSSHCheck(workspace)
    }
    private static func directSSHCheck(_ workspace: Workspace) throws {
        var server = Server(host: "split-fixture.invalid")
        server.user = "fixture"; server.port = "2222"
        workspace.connect(server)
        let source = workspace.selected!
        source.encoding = .utf8
        workspace.requestSplit(.horizontal)
        guard let copy = workspace.selected, copy.id != source.id,
              copy.sourceServer == source.sourceServer, copy.terminal !== source.terminal,
              copy.encoding == source.encoding, workspace.splitRequest == nil,
              workspace.layout(containing: source.id).leaves == [source.id, copy.id] else {
            throw ConfigurationError.invalid("Direct SSH split lost configuration or independent identity")
        }
        copy.isCodexSession = true
        let count = workspace.sessions.count
        workspace.requestSplit(.vertical)
        guard workspace.sessions.count == count, workspace.splitRequest?.target == copy.id else {
            throw ConfigurationError.invalid("Codex split must retain explicit session choice")
        }
        workspace.splitRequest = nil
        print("PASS: direct local/SSH splits, independent identity, focused nested target and Codex chooser fallback")
    }

    static func shortcuts(window: NSWindow, workspace: Workspace) throws {
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        let deadline = Date().addingTimeInterval(2)
        while NSApp.keyWindow !== window && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        func items(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0] + ($0.submenu.map(items) ?? []) } }
        let menuItems = NSApp.mainMenu.map(items) ?? []
        for (selector, axis, binding) in [("splitHorizontally", PaneAxis.horizontal, SplitShortcutPreferences.shared.value.horizontal),
                                           ("splitVertically", PaneAxis.vertical, SplitShortcutPreferences.shared.value.vertical)] {
            guard let item = menuItems.first(where: { $0.action.map(NSStringFromSelector) == selector }),
                  item.keyEquivalent == binding.key, item.keyEquivalentModifierMask == binding.modifiers else {
                throw ConfigurationError.invalid("Split shortcut missing or incorrect")
            }
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: binding.modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: binding.key.uppercased(), charactersIgnoringModifiers: binding.key.uppercased(),
                isARepeat: false, keyCode: binding.key == "h" ? 4 : 9)!
            guard let source = workspace.selected else { throw ConfigurationError.invalid("No split target") }
            let before = Set(workspace.sessions.map(\.id))
            let handled = SplitShortcutDispatch.handle(event, workspace: workspace)
            guard handled, workspace.splitRequest == nil, let created = workspace.selected,
                  !before.contains(created.id), workspace.layout(containing: source.id).leaves.contains(created.id) else {
                throw ConfigurationError.invalid("Split shortcut did not directly split the focused pane")
            }
            workspace.close(created); workspace.focusPane(source.id)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            guard NSApp.sendAction(item.action!, to: item.target, from: item), workspace.splitRequest == nil,
                  let menuCreated = workspace.selected, menuCreated.id != source.id else {
                throw ConfigurationError.invalid("Split menu action failed")
            }
            workspace.close(menuCreated); workspace.focusPane(source.id)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            workspace.requestSplit(axis, chooseSession: true)
            guard workspace.splitRequest?.target == source.id, workspace.splitRequest?.axis == axis else {
                throw ConfigurationError.invalid("Explicit split chooser unavailable")
            }
            workspace.splitRequest = nil
        }
        guard menuItems.contains(where: { $0.action.map(NSStringFromSelector) == "paste:" && $0.keyEquivalent == "v" && $0.keyEquivalentModifierMask == .command }),
              menuItems.first(where: { $0.action.map(NSStringFromSelector) == "showHistory" })?.keyEquivalent == "" else {
            throw ConfigurationError.invalid("Split shortcuts conflict with paste/history")
        }
        print("PASS: split keyboard shortcuts: key routing and native menu actions, direct active-pane split and explicit chooser, paste preserved and history conflict removed")
    }
}
