import AppKit
import SwiftUI
import MyTermCore

/// One native responder owns selection, context clicks and drag initiation.
/// No nested SwiftUI button/drag tracking or application-level mouse monitor.
struct SessionTabControl: NSViewRepresentable {
    @ObservedObject var workspace: Workspace
    @ObservedObject var session: TerminalSession
    func makeNSView(context: Context) -> SessionTabNativeView { SessionTabNativeView() }
    func updateNSView(_ view: SessionTabNativeView, context: Context) {
        view.configure(title: session.label, symbol: session.executable == "/usr/bin/ssh" ? "network" : "terminal",
                       selected: workspace.selectedID == session.id, sessionID: session.id)
        view.select = { [weak workspace] in workspace?.selectedID = session.id }
        view.close = { [weak workspace, weak session] in if let session { workspace?.close(session) } }
        view.move = { [weak workspace] source in workspace?.moveSessionTab(source, to: session.id) ?? false }
        view.identifier = NSUserInterfaceItemIdentifier("session.tab.menu." + session.id.uuidString)
        view.buildMenu = { [weak workspace, weak session] in
            guard let workspace, let session, workspace.sessions.contains(where: { $0 === session }) else { return nil }
            let menu = NSMenu()
            func add(_ title: String, action: @escaping () -> Void) {
                menu.addItem(SessionTabMenuItem(title: L10n.text(title), action: action))
            }
            add("复制会话（新连接）") { workspace.duplicate(session) }
            let logging = NSMenuItem(title: L10n.text("会话日志"), action: nil, keyEquivalent: "")
            let modes = NSMenu()
            for mode in HistoryLoggingMode.allCases {
                let item = SessionTabMenuItem(title: L10n.text(mode.title)) { workspace.setHistoryLogging(mode, for: session) }
                item.state = session.historyLogging == mode ? .on : .off
                modes.addItem(item)
            }
            logging.submenu = modes; menu.addItem(logging)
            add("更改标签名称…") { workspace.renameTab(session) }
            if session.sourceServer != nil { add("更改 SSH 配置…") { workspace.editConnection(session) } }
            if session.canReconnect { add("重新连接", action: session.reconnect) }
            menu.addItem(.separator())
            add("关闭会话") { workspace.close(session) }
            return menu
        }
    }
}

final class SessionTabNativeView: NSView, NSDraggingSource {
    var buildMenu: (() -> NSMenu?)?
    var select: (() -> Void)?
    var close: (() -> Void)?
    var move: ((UUID) -> Bool)?
    private var sessionID = UUID()
    private var down: NSEvent?
    // Some trackpad input reaches AppKit as a primary-typed event carrying
    // secondary button 1. A normal secondary-down may follow the synthetic pair.
    private var translatedSecondaryPress: NSEvent?
    private var selected = false
    private var targeted = false
    private let title = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let closeButton = TabBarNativeButton()
    private static let dragType = SessionTabDrag.pasteboardType
    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 12)
        title.lineBreakMode = .byTruncatingTail
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        closeButton.imagePosition = .imageOnly
        closeButton.target = closeButton
        closeButton.action = #selector(TabBarNativeButton.activate)
        closeButton.onActivate = { [weak self] in self?.close?() }
        addSubview(icon); addSubview(title); addSubview(closeButton)
        registerForDraggedTypes([Self.dragType])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(title text: String, symbol: String, selected: Bool, sessionID: UUID) {
        if title.stringValue != text { title.stringValue = text; invalidateIntrinsicContentSize() }
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        self.selected = selected; self.sessionID = sessionID
        closeButton.toolTip = L10n.text("关闭会话")
        closeButton.setAccessibilityLabel(L10n.text("关闭会话"))
        setAccessibilityLabel(text)
        needsDisplay = true; needsLayout = true
    }
    override var intrinsicContentSize: NSSize {
        NSSize(width: max(90, min(340, title.intrinsicContentSize.width + 60)), height: 30)
    }
    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 9, y: (bounds.height - 14) / 2, width: 14, height: 14)
        title.frame = NSRect(x: 28, y: (bounds.height - 16) / 2, width: max(0, bounds.width - 55), height: 16)
        closeButton.frame = NSRect(x: bounds.width - 24, y: 0, width: 24, height: bounds.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        if selected { NSColor.labelColor.withAlphaComponent(0.1).setFill(); shape.fill() }
        if targeted { NSColor.controlAccentColor.setStroke(); shape.lineWidth = 2; shape.stroke() }
    }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard !isHidden, bounds.contains(local) else { return nil }
        // Labels and transparent padding all belong to the tab. Only the close
        // button has its own left-click action; right clicks use the tab menu.
        if closeButton.frame.contains(local), NSApp.currentEvent?.type != .rightMouseDown, NSApp.currentEvent?.buttonNumber != 1,
           NSApp.currentEvent?.modifierFlags.contains(.control) != true { return closeButton }
        return self
    }
    override func mouseDown(with event: NSEvent) {
        if event.buttonNumber == 1 {
            translatedSecondaryPress = event
            guard let secondary = NSEvent.mouseEvent(with: .rightMouseDown, location: event.locationInWindow,
                modifierFlags: event.modifierFlags, timestamp: event.timestamp, windowNumber: event.windowNumber,
                context: nil, eventNumber: event.eventNumber, clickCount: event.clickCount, pressure: event.pressure) else { return }
            showMenu(secondary)
            return
        }
        if event.modifierFlags.contains(.control) { showMenu(event); return }
        down = event
    }
    override func mouseUp(with event: NSEvent) {
        guard event.buttonNumber != 1, down != nil else { return }
        down = nil
        if bounds.contains(convert(event.locationInWindow, from: nil)) { select?() }
    }
    override func rightMouseDown(with event: NSEvent) {
        if let translated = translatedSecondaryPress {
            translatedSecondaryPress = nil
            let delta = event.timestamp - translated.timestamp
            if delta >= 0 && delta < 0.05 && event.clickCount == translated.clickCount &&
                hypot(event.locationInWindow.x - translated.locationInWindow.x,
                      event.locationInWindow.y - translated.locationInWindow.y) < 2 { return }
        }
        showMenu(event)
    }
    override func rightMouseUp(with event: NSEvent) {
        // A single physical press opens at most one menu, on press rather than release.
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        // AppKit can request a menu through a child responder (e.g. the close
        // button) instead of calling this view's rightMouseDown directly.
        select?()
        return buildMenu?()
    }
    private func showMenu(_ event: NSEvent) {
        down = nil
        select?()
        guard let menu = buildMenu?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    override func accessibilityPerformPress() -> Bool { select?(); return true }
    override func mouseDragged(with event: NSEvent) {
        guard let down, hypot(event.locationInWindow.x - down.locationInWindow.x,
                              event.locationInWindow.y - down.locationInWindow.y) >= 4 else { return }
        self.down = nil
        let item = SessionTabDrag(id: sessionID).pasteboardItem
        let drag = NSDraggingItem(pasteboardWriter: item)
        let image = NSImage(size: bounds.size)
        if let bitmap = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: bitmap); image.addRepresentation(bitmap)
        }
        drag.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [drag], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    private func draggedID(_ sender: NSDraggingInfo) -> UUID? {
        guard sender.draggingSource is SessionTabNativeView else { return nil }
        return SessionTabDrag.decode(sender.draggingPasteboard)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        targeted = draggedID(sender) != nil; needsDisplay = true
        return targeted ? .move : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { targeted = false; needsDisplay = true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        targeted = false; needsDisplay = true
        guard let id = draggedID(sender) else { return false }
        return move?(id) ?? false
    }
    override func draggingEnded(_ sender: NSDraggingInfo) { targeted = false; needsDisplay = true }
}

private final class SessionTabMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(performAction), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func performAction() { handler() }
}
