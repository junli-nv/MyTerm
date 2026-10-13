import AppKit
import MyTermCore

/// Real event-loop context clicks after a single selection, including rebuilding
/// the SwiftUI strip when switching terminals. Never double-click to arm a menu.
enum SessionTabContextMenuCheck {
    static func run(window: NSWindow, workspace: Workspace) throws {
        let original = workspace.selectedID
        defer { workspace.selectedID = original }
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw ConfigurationError.invalid("Tab context menu: " + message) }
        }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.08)); window.contentView?.layoutSubtreeIfNeeded() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func tabView(_ id: UUID) throws -> SessionTabNativeView {
            guard let view = descendants(window.contentView!).compactMap({ $0 as? SessionTabNativeView }).first(where: {
                $0.identifier?.rawValue == "session.tab.menu." + id.uuidString
            }), view.visibleRect.width > 20 else { throw ConfigurationError.invalid("Tab menu target missing or clipped") }
            return view
        }
        func event(_ type: NSEvent.EventType, point: NSPoint, flags: NSEvent.ModifierFlags = [],
                   secondaryButton: Bool = false, timestamp: TimeInterval? = nil) -> NSEvent {
            let result = NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: timestamp ?? ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
            guard secondaryButton else { return result }
            // Reproduce the observed physical trackpad sequence: left-typed
            // events whose underlying button number is the secondary button.
            let cgEvent = result.cgEvent!
            cgEvent.setIntegerValueField(.mouseEventButtonNumber, value: 1)
            return NSEvent(cgEvent: cgEvent)!
        }
        let targets = Array(workspace.sessions.prefix(2))
        try require(targets.count == 2, "Two tabs required")
        for target in targets + targets {
            settle()
            let view = try tabView(target.id)
            let point = view.convert(NSPoint(x: min(50, view.bounds.width * 0.5), y: view.bounds.midY), to: nil)
            // Go through NSWindow directly, without an application monitor or
            // fabricated double-click. Native handlers must finish each gesture.
            window.sendEvent(event(.leftMouseDown, point: point))
            window.sendEvent(event(.leftMouseUp, point: point))
            try require(workspace.selectedID == target.id, "Single click failed to select tab")
            settle()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            try require(window.firstResponder === target.terminal, "Selected terminal did not receive keyboard focus")
            let active = try tabView(target.id)
            let locations = [NSPoint(x: 2, y: active.bounds.midY),
                             NSPoint(x: active.bounds.width * 0.5, y: 2),
                             NSPoint(x: active.bounds.width * 0.5, y: active.bounds.height - 2),
                             NSPoint(x: 17, y: active.bounds.midY),
                             NSPoint(x: active.bounds.width - 2, y: active.bounds.midY),
                             NSPoint(x: 35, y: active.bounds.midY)]
            for (index, location) in locations.enumerated() {
                let controlClick = index == 3
                let translatedClick = index == 5
                let contextPoint = active.convert(location, to: nil)
                let pressTime = ProcessInfo.processInfo.systemUptime
                var opened = false, ended = false, survivedRelease = false
                var openings = 0
                var releaseTimer: Timer?, closeTimer: Timer?
                let endObserver = NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { _ in ended = true }
                let observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { notification in
                    guard let menu = notification.object as? NSMenu,
                          menu.items.first?.title == L10n.text("选中会话") else { return }
                    opened = true
                    openings += 1
                    ended = false
                    releaseTimer = Timer(timeInterval: 0.04, repeats: false) { _ in
                        if translatedClick {
                            NSApp.postEvent(event(.leftMouseUp, point: contextPoint, secondaryButton: true), atStart: true)
                        }
                        NSApp.postEvent(event(controlClick ? .leftMouseUp : .rightMouseUp,
                                              point: contextPoint, flags: controlClick ? .control : []), atStart: true)
                    }
                    closeTimer = Timer(timeInterval: 0.12, repeats: false) { _ in
                        survivedRelease = !ended
                        menu.cancelTracking()
                    }
                    for timer in [releaseTimer!, closeTimer!] {
                        RunLoop.main.add(timer, forMode: .eventTracking)
                        RunLoop.main.add(timer, forMode: .default)
                    }
                }
                window.sendEvent(event(controlClick || translatedClick ? .leftMouseDown : .rightMouseDown, point: contextPoint,
                                       flags: controlClick ? .control : [], secondaryButton: translatedClick, timestamp: pressTime))
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                if translatedClick {
                    try require(openings == 1 && survivedRelease, "Translated secondary press did not leave one usable menu")
                    // A matching normal event may follow the synthetic pair.
                    // It must not reopen a dismissed menu for the same press.
                    window.sendEvent(event(.rightMouseDown, point: contextPoint, secondaryButton: true, timestamp: pressTime + 0.001))
                    try require(openings == 1, "One physical press opened the menu twice")
                    window.sendEvent(event(.rightMouseDown, point: contextPoint, secondaryButton: true, timestamp: pressTime + 1))
                    try require(openings == 2, "A later independent secondary press was ignored")
                }
                releaseTimer?.invalidate(); closeTimer?.invalidate()
                NotificationCenter.default.removeObserver(observer)
                NotificationCenter.default.removeObserver(endObserver)
                try require(opened && survivedRelease, "Context menu missing or dismissed on release at \(location)")
            }
            let menu = try tabView(target.id).buildMenu!()!
            try require(menu.items.contains(where: { $0.title == L10n.text("复制会话（新连接）") }) &&
                        menu.items.contains(where: { $0.title == L10n.text("关闭会话") }), "Menu actions missing")
            workspace.selectedID = targets.first(where: { $0.id != target.id })!.id
            menu.performActionForItem(at: 0)
            try require(workspace.selectedID == target.id, "Menu action targeted the other tab")
        }
        let closing = TerminalSession(label: "Close fixture", executable: "/bin/false", arguments: [])
        workspace.sessions.append(closing); workspace.selectedID = closing.id
        settle()
        let closingView = try tabView(closing.id)
        let closePoint = closingView.convert(NSPoint(x: closingView.bounds.width - 12, y: closingView.bounds.midY), to: nil)
        NSApp.postEvent(event(.leftMouseUp, point: closePoint), atStart: true)
        window.sendEvent(event(.leftMouseDown, point: closePoint))
        settle()
        try require(!workspace.sessions.contains(where: { $0.id == closing.id }), "Native close button did not close its tab")
        print("PASS: tab menus: single-click focus, right/Control and translated trackpad press-release, duplicate suppression, edge hits, persistent menu and correct target")
    }
}
