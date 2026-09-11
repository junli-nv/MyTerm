import AppKit
import SwiftUI

/// Only the unused tab-strip space handles window gestures.
struct TabBarDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> TabBarDragView { TabBarDragView() }
    func updateNSView(_ nsView: TabBarDragView, context: Context) {}
}

final class TabBarDragView: NSView {
    private var mouseDownEvent: NSEvent?
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 {
            mouseDownEvent = nil
            window.performZoom(nil)
        } else if event.clickCount == 1 {
            mouseDownEvent = event
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        mouseDownEvent = nil
        window?.performDrag(with: down)
    }
    override func mouseUp(with event: NSEvent) { mouseDownEvent = nil }
}

/// Native title-strip buttons have an explicit hit area, including transparent icon padding.
struct TabBarButton: NSViewRepresentable {
    let symbol: String
    let tooltip: String
    let identifier: String
    var selected = false
    let action: () -> Void

    func makeNSView(context: Context) -> TabBarNativeButton {
        let button = TabBarNativeButton()
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryChange)
        button.target = button
        button.action = #selector(TabBarNativeButton.activate)
        return button
    }
    func updateNSView(_ button: TabBarNativeButton, context: Context) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: L10n.text(tooltip))
        button.toolTip = L10n.text(tooltip)
        button.setAccessibilityLabel(L10n.text(tooltip))
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.contentTintColor = selected ? .controlAccentColor : .secondaryLabelColor
        button.onActivate = action
    }
}

final class TabBarNativeButton: NSButton {
    var onActivate: (() -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc func activate() { onActivate?() }
}
