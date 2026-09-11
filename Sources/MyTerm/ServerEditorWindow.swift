import AppKit
import SwiftUI
import MyTermCore

final class ServerEditorWindowController: NSWindowController, NSWindowDelegate {
    static let shared = ServerEditorWindowController()
    private weak var workspace: Workspace?
    private var languageObserver: NSObjectProtocol?
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = L10n.text("SSH 服务器")
        window.contentMinSize = NSSize(width: 640, height: 480)
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        super.init(window: window)
        window.delegate = self
        languageObserver = NotificationCenter.default.addObserver(forName: LanguagePreferences.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.window?.title = L10n.text("SSH 服务器")
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) } }
    func present(server: Server, workspace: Workspace) {
        self.workspace = workspace
        window?.contentView = NSHostingView(rootView: ServerEditor(server: server, workspace: workspace,
            onClose: { [weak self] in self?.close() }, onZoom: { [weak self] in self?.window?.performZoom(nil) }))
        if window?.isVisible != true { window?.center() }
        showWindow(nil); window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { workspace?.editor = nil; workspace = nil }
}

/// Keep the long configuration form scrollable even with macOS overlay-scrollbar preferences.
struct EditorScrollbars: NSViewRepresentable {
    func makeNSView(context: Context) -> EditorScrollMarker { EditorScrollMarker() }
    func updateNSView(_ view: EditorScrollMarker, context: Context) { view.configure() }
}
final class EditorScrollMarker: NSView {
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); configure() }
    override func layout() { super.layout(); configure() }
    func configure() {
        func scrollIn(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollIn($0) }.first
        }
        guard let scroll = enclosingScrollView ?? window?.contentView.flatMap({ scrollIn($0) }) else { return }
        guard scroll.identifier?.rawValue != "ssh.editor.scroll" || scroll.autohidesScrollers || scroll.scrollerStyle != .legacy else { return }
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        scroll.scrollerStyle = .legacy
        scroll.hasHorizontalScroller = false
        scroll.identifier = NSUserInterfaceItemIdentifier("ssh.editor.scroll")
    }
}

struct EditorTextField: View {
    let title: String
    @Binding var text: String
    let prompt: String?
    init(title: String, text: Binding<String>, prompt: String? = nil) {
        self.title = title; self._text = text; self.prompt = prompt
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text(title)).fixedSize(horizontal: false, vertical: true)
            TextField("", text: $text, prompt: prompt.map { Text(L10n.text($0)) }).accessibilityLabel(L10n.text(title))
                .textFieldStyle(.roundedBorder)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
