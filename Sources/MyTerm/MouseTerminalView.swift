import AppKit
import SwiftTerm
import MyTermCore
import Combine

class MouseTerminalView: LocalProcessTerminalView {
    var appliedANSI: [ThemeColor]?
    private var highlighting: TerminalOutputHighlighter?
    private var highlightSubscription: AnyCancellable?
    func configureOutputHighlighting(isSSH: Bool, preferences: OutputHighlightPreferences = .shared) {
        highlightSubscription = preferences.$configuration.sink { [weak self] configuration in
            guard let self else { return }
            if !configuration.enabled {
                self.highlighting = nil
                self.rowForegroundProvider = nil
                return
            }
            guard let highlighter = try? TerminalOutputHighlighter(configuration) else { return }
            self.highlighting = highlighter
            self.rowForegroundProvider = { [weak self] row, line, columns in
                guard let self else { return [:] }
                return self.highlighting?.colors(terminal: self.getTerminal(), row: row, line: line, columns: columns, isSSH: isSSH) ?? [:]
            }
        }
    }
    var preferences = MousePreferences.shared
    var zmodem: ZmodemBridge?
    var canUploadFiles: (() -> Bool)?
    var trzszEnabled = false
    var dragUploadProtocol: DragUploadProtocol = .automatic
    private var incomingText: TerminalTranscoder?
    private var outgoingText: TerminalTranscoder?
    func setEncoding(_ encoding: TerminalEncoding) throws {
        let incoming = encoding == .utf8 ? nil : try TerminalTranscoder(from: encoding, to: .utf8)
        let outgoing = encoding == .utf8 ? nil : try TerminalTranscoder(from: .utf8, to: encoding)
        incomingText = incoming; outgoingText = outgoing
    }
    private var reconnectMonitor: Any?
    private var zoomMonitor: Any?
    private var fontZoom = FontZoomGesture()
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let zoomMonitor { NSEvent.removeMonitor(zoomMonitor); self.zoomMonitor = nil }
        fontZoom = FontZoomGesture()
        guard window != nil else { return }
        zoomMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.window, event.window === window,
                  self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
            let control = event.modifierFlags.contains(.control)
            let change = self.fontZoom.consume(delta: event.scrollingDeltaY,
                inverted: event.isDirectionInvertedFromDevice, precise: event.hasPreciseScrollingDeltas,
                control: control, momentum: !event.momentumPhase.isEmpty,
                began: event.phase.contains(.began), timestamp: event.timestamp)
            guard let change else { return event }
            if change != 0 {
                let preferences = ThemePreferences.shared
                let size = min(36, max(9, preferences.theme.fontSize + change))
                if size != preferences.theme.fontSize { preferences.theme.fontSize = size }
            }
            return nil
        }
    }
    var reconnectHandler: (() -> Void)? {
        didSet {
            if let reconnectMonitor { NSEvent.removeMonitor(reconnectMonitor); self.reconnectMonitor = nil }
            guard reconnectHandler != nil else { return }
            reconnectMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.window === event.window, self.window?.firstResponder === self else { return event }
                return self.handleReconnectKey(event) ? nil : event
            }
        }
    }
    deinit {
        if let reconnectMonitor { NSEvent.removeMonitor(reconnectMonitor) }
        if let zoomMonitor { NSEvent.removeMonitor(zoomMonitor) }
    }
    func handleReconnectKey(_ event: NSEvent) -> Bool {
        guard let reconnectHandler, event.charactersIgnoringModifiers?.lowercased() == "r",
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        reconnectHandler(); return true
    }

    override func bell(source: Terminal) {
        guard !preferences.disableBell else { return }
        super.bell(source: source)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canUploadFiles?() == true, zmodem?.active == false, zmodem?.awaitingReceiver == false,
              !droppedFiles(sender).isEmpty else { return [] }
        return .copy
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard canUploadFiles?() == true else { return false }
        return uploadDroppedFiles(droppedFiles(sender))
    }
    @discardableResult func uploadDroppedFiles(_ urls: [URL]) -> Bool {
        guard zmodem?.active != true, zmodem?.awaitingReceiver != true else { return false }
        let useTrzsz = trzszEnabled && (dragUploadProtocol == .trzsz ||
            (dragUploadProtocol == .automatic && getTerminal().isCurrentBufferAlternate))
        if useTrzsz {
            do {
                let data = try TrzszIntegration.dragInput(urls)
                process.send(data: Array(data)[...])
                return true
            } catch { zmodem?.status = error.localizedDescription; return false }
        }
        return zmodem?.uploadDroppedFiles(urls) == true
    }
    private func droppedFiles(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        let visible = zmodem?.consume(Data(slice)) ?? Data(slice)
        let bytes = incomingText?.convert(Array(visible)) ?? Array(visible)
        if !bytes.isEmpty { super.dataReceived(slice: bytes[...]) }
    }
    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard reconnectHandler == nil else { return }
        guard zmodem?.active != true, zmodem?.awaitingReceiver != true else { return }
        let bytes = outgoingText?.convert(Array(data)) ?? Array(data)
        if !bytes.isEmpty { super.send(source: source, data: bytes[...]) }
    }

    override func mouseDown(with event: NSEvent) {
        doubleClickSelectsLogicalLine = true
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        // Mouse-aware remote applications own ordinary left clicks; Shift selects locally.
        let remoteMouse = allowMouseReporting && getTerminal().mouseMode != .off
            && !event.modifierFlags.contains(.shift)
        guard preferences.copyOnSelection, !remoteMouse,
              selection.active, !selection.getSelectedText().isEmpty else { return }
        copy(self)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if let menu = menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            // Keep SwiftTerm's paste path, including bracketed paste for supported shells.
            paste(self)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        // The complete action is handled on mouse down; don't paste or forward a release twice.
    }

    // Join verified soft wraps in every buffer; hard line boundaries are maintained
    // by the emulator as text is advanced, erased and reflowed.
    override func copy(_ sender: Any) {
        writeSelection(preserveLineBreaks: false)
    }
    @objc func copyPreservingScreenLines(_ sender: Any) { writeSelection(preserveLineBreaks: true) }
    private func writeSelection(preserveLineBreaks: Bool) {
        let text = selection.getSelectedText(preserveLineBreaks: preserveLineBreaks)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if preferences.rightClickPastes && !event.modifierFlags.contains(.shift) { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let copyItem = menu.addItem(withTitle: L10n.text("复制"), action: #selector(copy(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.isEnabled = selection.active && !selection.getSelectedText().isEmpty
        let joined = menu.addItem(withTitle: L10n.text("复制（保留屏幕换行）"), action: #selector(copyPreservingScreenLines(_:)), keyEquivalent: "")
        joined.target = self; joined.isEnabled = copyItem.isEnabled
        let pasteItem = menu.addItem(withTitle: L10n.text("粘贴"), action: #selector(paste(_:)), keyEquivalent: "")
        pasteItem.target = self
        pasteItem.isEnabled = NSPasteboard.general.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.string.rawValue])
        let selectItem = menu.addItem(withTitle: L10n.text("全选"), action: #selector(selectAll(_:)), keyEquivalent: "")
        selectItem.target = self
        menu.addItem(.separator())
        let settingsItem = menu.addItem(withTitle: L10n.text("鼠标与粘贴设置…"), action: #selector(showMouseSettings), keyEquivalent: "")
        settingsItem.target = self
        return menu
    }

    @objc private func showMouseSettings() { MouseSettingsController.shared.present() }
}
