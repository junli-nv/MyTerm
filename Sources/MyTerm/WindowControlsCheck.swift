import AppKit
import MyTermCore

/// Real mouse routing and layout checks, compiled identically into Debug and Release.
/// Requires --smoke-test so settings/history are never persisted.
final class WindowControlsCheck {
    private let window: NSWindow
    private let workspace: Workspace
    private var phase = 0
    private var timer: Timer?
    private var baseline = NSRect.zero
    private var originalWindow = NSRect.zero
    private var tabAreaBeforeSwitch = NSRect.zero
    private var fixture: TerminalSession!
    private var local: TerminalSession!
    private var deadline = Date().addingTimeInterval(30)

    private init(window: NSWindow, workspace: Workspace) { self.window = window; self.workspace = workspace }
    static func run(window: NSWindow, workspace: Workspace) {
        let check = WindowControlsCheck(window: window, workspace: workspace)
        do {
            try TmuxPrefixInputCheck.run()
            try TerminalCopyCheck.run()
            try SSHDisconnectCheck.run()
            try OutputHighlightCheck.run()
            try ThemeColorCheck.run()
            ThemeLayoutCheck.run()
            try SettingsTabsCheck.run()
            try ServerEditorLayoutCheck.run()
            check.require(!window.isOpaque && window.backgroundColor == .clear, "Window must composite terminal background opacity")
            window.makeKeyAndOrderFront(nil)
            check.local = workspace.selected!
            let server = Server(host: "localhost")
            let context = try SSHLaunchContext(server: server)
            check.fixture = TerminalSession(label: "SFTP panel fixture", executable: "/bin/bash", arguments: ["--noprofile", "--norc", "-i"], server: server, context: context, directory: "/tmp")
            workspace.sessions.append(check.fixture)
            workspace.selectedID = check.fixture.id
            // Earlier suites have their own bounded waits; start this phase budget now.
            check.deadline = Date().addingTimeInterval(30)
            check.timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in check.tick() }
        } catch { check.fail(error.localizedDescription) }
    }
    private func fail(_ message: String) -> Never {
        workspace.stopAll()
        fputs("FAIL: window controls phase \(phase): \(message)\n", stderr)
        exit(1)
    }
    private func require(_ condition: Bool, _ message: String) { if !condition { fail(message) } }
    private func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap { descendants($0) } }
    private func button(_ id: String) -> NSButton {
        guard let result = descendants(window.contentView!).compactMap({ $0 as? NSButton }).first(where: { $0.identifier?.rawValue == id }) else { fail("Missing \(id)") }
        require(result.bounds.width >= 28 && result.bounds.height >= 28, "Button target is too small")
        return result
    }
    private func click(_ point: NSPoint, count: Int = 1) {
        let now = ProcessInfo.processInfo.systemUptime
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: now, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: count, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: now + 0.01, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: count, pressure: 0)!
        // Native button tracking consumes its mouse-up in the event loop.
        NSApp.postEvent(up, atStart: true)
        window.sendEvent(down)
    }
    private func clickButton(_ id: String, edge: Bool = false) {
        let control = button(id)
        let localPoint = NSPoint(x: edge ? 2 : control.bounds.midX, y: control.bounds.midY)
        click(control.convert(localPoint, to: nil))
    }
    private func doubleClickBlank() {
        guard let area = descendants(window.contentView!).first(where: { $0 is TabBarDragView }) else { fail("Missing blank drag area") }
        require(area.bounds.width > 80, "Blank area must fill available tab strip")
        let point = area.convert(NSPoint(x: area.bounds.midX, y: area.bounds.midY), to: nil)
        click(point)
        click(point, count: 2)
    }
    private func terminalFrame() -> NSRect {
        guard let scroll = fixture.terminal.enclosingScrollView else { fail("No terminal scroll view") }
        return scroll.convert(scroll.bounds, to: nil)
    }
    private func tick() {
        if Date() > deadline { fail("Timed out") }
        window.contentView?.layoutSubtreeIfNeeded()
        switch phase {
        case 0:
            guard fixture.isRunning, fixture.terminal.window != nil else { return }
            require(!fixture.statusBarVisible && !fixture.showSFTP && !workspace.sidebarVisible, "Panels must start hidden")
            baseline = terminalFrame()
            require(window.frame.height - baseline.maxY <= 34, "Title strip regressed to two rows")
            clickButton("tabbar.status", edge: true)
        case 1:
            require(fixture.statusBarVisible, "Bottom bar did not open")
            require(terminalFrame().height < baseline.height - 10, "Bottom bar state changed but layout did not")
            clickButton("tabbar.status")
        case 2:
            require(!fixture.statusBarVisible && abs(terminalFrame().height - baseline.height) < 2, "Bottom bar did not close")
            clickButton("tabbar.sftp", edge: true)
        case 3:
            require(fixture.showSFTP && terminalFrame().width < baseline.width - 150, "SFTP panel did not open")
            clickButton("tabbar.sftp")
        case 4:
            require(!fixture.showSFTP && abs(terminalFrame().width - baseline.width) < 2, "SFTP panel did not close")
            clickButton("tabbar.sidebar", edge: true)
        case 5:
            require(workspace.sidebarVisible && terminalFrame().width < baseline.width - 150, "Sidebar did not open")
            clickButton("tabbar.sidebar")
        case 6:
            require(!workspace.sidebarVisible && abs(terminalFrame().width - baseline.width) < 2, "Sidebar did not close")
            originalWindow = window.frame
            doubleClickBlank()
        case 7:
            require(window.frame != originalWindow && window.isZoomed, "Double-click did not maximize")
            doubleClickBlank()
        case 8:
            require(abs(window.frame.width - originalWindow.width) < 2 && abs(window.frame.height - originalWindow.height) < 2, "Double-click did not restore")
            guard let area = descendants(window.contentView!).first(where: { $0 is TabBarDragView }) else { fail("No tab drag area") }
            tabAreaBeforeSwitch = area.convert(area.bounds, to: nil)
            let sftp = button("tabbar.sftp")
            require(sftp.convert(sftp.bounds, to: nil).minX > window.contentView!.bounds.width - 90, "SFTP toggle must sit beside the right-hand plus button")
            workspace.selectedID = local.id
        case 9:
            guard let area = descendants(window.contentView!).first(where: { $0 is TabBarDragView }) else { fail("No tab drag area") }
            let after = area.convert(area.bounds, to: nil)
            require(abs(after.minX - tabAreaBeforeSwitch.minX) < 1 && abs(after.width - tabAreaBeforeSwitch.width) < 1, "Switching SSH/local shifted the tab strip")
            require(!descendants(window.contentView!).contains(where: { $0.identifier?.rawValue == "tabbar.sftp" }), "Local shell must not expose SFTP control")
            clickButton("tabbar.status")
        case 10:
            require(local.statusBarVisible && !fixture.statusBarVisible, "Tab switch button changed wrong session")
            workspace.selectedID = fixture.id
        case 11:
            clickButton("tabbar.status")
        case 12:
            require(fixture.statusBarVisible && local.statusBarVisible, "Session button lost its target after switching back")
            print("PASS: window controls: actual mouse clicks, padded targets, bottom bar, sidebar, SFTP panel, double-click maximize/restore, per-tab state and stable SSH/local tab geometry")
            timer?.invalidate(); timer = nil
            workspace.stopAll()
            NSApp.terminate(nil)
            return
        default: fail("Unknown phase")
        }
        phase += 1
    }
}
