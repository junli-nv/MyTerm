import SwiftUI

/// The window shares its owning SSH session's model; closing it docks without disconnecting.
final class SFTPWindowController: NSWindowController, NSWindowDelegate {
    private weak var model: SFTPModel?
    init(model: SFTPModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "SFTP — " + model.displayName
        window.minSize = NSSize(width: 360, height: 400)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SFTPPanel(model: model))
        super.init(window: window)
        window.delegate = self; window.center()
    }
    required init?(coder: NSCoder) { nil }
    func windowWillClose(_ notification: Notification) { model?.windowClosed() }
}
