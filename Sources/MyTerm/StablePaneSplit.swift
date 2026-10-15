import AppKit
import SwiftUI
import MyTermCore

/// Owns sizing rather than letting hosted content's intrinsic size redistribute siblings.
struct StablePaneSplit: NSViewRepresentable {
    let axis: PaneAxis
    let first: AnyView
    let second: AnyView
    let fraction: CGFloat
    let saveFraction: (CGFloat) -> Void

    func makeNSView(context: Context) -> PaneSplitView {
        let view = PaneSplitView()
        view.isVertical = axis == .vertical
        view.dividerStyle = .thin
        view.fraction = fraction
        view.saveFraction = saveFraction
        view.addArrangedSubview(NSHostingView(rootView: first))
        view.addArrangedSubview(NSHostingView(rootView: second))
        return view
    }

    static func dismantleNSView(_ view: PaneSplitView, coordinator: ()) {
        // Detached hosts must stop observing the workspace before a terminal is reparented.
        for case let host as NSHostingView<AnyView> in view.arrangedSubviews {
            host.rootView = AnyView(EmptyView())
        }
        view.saveFraction = { _ in }
    }

    func updateNSView(_ view: PaneSplitView, context: Context) {
        view.saveFraction = saveFraction
        (view.arrangedSubviews[0] as? NSHostingView<AnyView>)?.rootView = first
        (view.arrangedSubviews[1] as? NSHostingView<AnyView>)?.rootView = second
        view.resizeSubviews(withOldSize: view.bounds.size)
    }
}

final class PaneSplitView: NSSplitView, NSSplitViewDelegate {
    var fraction: CGFloat = 0.5
    var saveFraction: (CGFloat) -> Void = { _ in }
    private var arranging = false
    private var dragging = false
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        delegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        guard arrangedSubviews.count == 2, !arranging else { return }
        arranging = true
        defer { arranging = false }
        let available = max(0, (isVertical ? bounds.width : bounds.height) - dividerThickness)
        let firstSize = (available * fraction).rounded(.down)
        if isVertical {
            arrangedSubviews[0].frame = NSRect(x: 0, y: 0, width: firstSize, height: bounds.height)
            arrangedSubviews[1].frame = NSRect(x: firstSize + dividerThickness, y: 0,
                width: available - firstSize, height: bounds.height)
        } else {
            arrangedSubviews[0].frame = NSRect(x: 0, y: 0, width: bounds.width, height: firstSize)
            arrangedSubviews[1].frame = NSRect(x: 0, y: firstSize + dividerThickness,
                width: bounds.width, height: available - firstSize)
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragging = true
        defer { dragging = false }
        super.mouseDown(with: event)
        rememberPosition()
    }

    override func setPosition(_ position: CGFloat, ofDividerAt dividerIndex: Int) {
        super.setPosition(position, ofDividerAt: dividerIndex)
        rememberPosition()
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        if dragging { rememberPosition() }
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        min(isVertical ? 240 : 140, max(0, ((isVertical ? bounds.width : bounds.height) - dividerThickness) / 2))
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        let available = max(0, (isVertical ? bounds.width : bounds.height) - dividerThickness)
        return available - min(isVertical ? 240 : 140, available / 2)
    }

    private func rememberPosition() {
        guard !arranging, let first = arrangedSubviews.first else { return }
        let available = (isVertical ? bounds.width : bounds.height) - dividerThickness
        guard available > 0 else { return }
        fraction = min(1, max(0, (isVertical ? first.frame.width : first.frame.height) / available))
        saveFraction(fraction)
    }
}
