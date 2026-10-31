import AppKit
import MyTermCore

/// Per-view metadata only: never retain keystrokes or process output.
final class TerminalDiagnosticTrace {
    let id = UUID()
    private var sequence = 0
    private var pending: Int?
    private var lastOutput = 0.0, outputBytes = 0
    static func state(_ view: MouseTerminalView) -> TerminalDiagnosticLog.State {
        let terminal = view.getTerminal()
        return .init(columns: terminal.cols, rows: terminal.rows, viewportRow: terminal.buffer.yDisp,
                     scrollPosition: view.scrollPosition, alternate: terminal.isDisplayBufferAlternate,
                     selection: view.selection.active, composing: view.hasMarkedText(),
                     focused: view.window?.firstResponder === view, keyboardFlags: UInt32(clamping: terminal.keyboardEnhancementFlags.rawValue),
                     mouseReporting: view.allowMouseReporting && terminal.mouseMode != .off,
                     applicationScrolling: view.usesApplicationScrolling)
    }
    func record(_ event: TerminalDiagnosticLog.Event, view: MouseTerminalView) {
        let log = TerminalDiagnostics.shared.log
        guard log.isRecording() else { return }
        log.record(event, terminal: id, state: Self.state(view))
    }
    func beginReturn(_ event: NSEvent, view: MouseTerminalView, up: Bool = false) {
        guard [UInt16(36), 76].contains(event.keyCode), TerminalDiagnostics.shared.log.isRecording() else { return }
        if !up { sequence += 1 }
        pending = sequence
        TerminalDiagnostics.shared.log.record(up ? .returnUp : .returnDown, terminal: id, sequence: sequence,
            modifiers: event.modifierFlags.intersection([.shift, .control, .option, .command]).rawValue,
            repeated: event.isARepeat, state: Self.state(view))
    }
    func endReturn(view: MouseTerminalView) {
        guard let pending else { return }
        TerminalDiagnostics.shared.log.record(.returnFinished, terminal: id, sequence: pending, state: Self.state(view))
        self.pending = nil
    }
    func sent(_ bytes: [UInt8], view: MouseTerminalView) {
        guard let pending else { return }
        let kind: TerminalDiagnosticLog.InputKind = bytes == [13] ? .carriageReturn : bytes == [10] ? .lineFeed : bytes.first == 27 ? .escapeSequence : .text
        TerminalDiagnostics.shared.log.record(.inputSent, terminal: id, sequence: pending, byteCount: bytes.count,
                                              input: kind, state: Self.state(view))
    }
    func output(count: Int, view: MouseTerminalView) {
        guard TerminalDiagnostics.shared.log.isRecording() else { outputBytes = 0; return }
        outputBytes += count
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastOutput >= 0.25 else { return }
        lastOutput = now
        TerminalDiagnostics.shared.log.record(.output, terminal: id, byteCount: outputBytes, state: Self.state(view))
        outputBytes = 0
    }
}
