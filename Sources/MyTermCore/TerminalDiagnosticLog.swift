import Foundation

/// Deliberately accepts no terminal text, key characters, paths, names or addresses.
/// The fixed schema prevents a caller from accidentally exporting session contents.
public final class TerminalDiagnosticLog {
    public enum Event: String, Codable { case started, stopped, marker, output, returnDown, returnUp, returnFinished, inputSent, compositionCommit, focus, scroll }
    public enum InputKind: String, Codable { case none, carriageReturn, lineFeed, escapeSequence, text }
    public struct State: Codable {
        public var columns: Int, rows: Int, viewportRow: Int
        public var scrollPosition: Double
        public var alternate: Bool, selection: Bool, composing: Bool, focused: Bool
        public var keyboardFlags: UInt32
        public init(columns: Int = 0, rows: Int = 0, viewportRow: Int = 0, scrollPosition: Double = 1,
                    alternate: Bool = false, selection: Bool = false, composing: Bool = false,
                    focused: Bool = false, keyboardFlags: UInt32 = 0) {
            self.columns = columns; self.rows = rows; self.viewportRow = viewportRow; self.scrollPosition = scrollPosition
            self.alternate = alternate; self.selection = selection; self.composing = composing
            self.focused = focused; self.keyboardFlags = keyboardFlags
        }
    }
    public struct Entry: Codable {
        public let time: Date, event: Event, terminal: UUID?, sequence: Int?, byteCount: Int
        public let input: InputKind, modifiers: UInt, repeated: Bool, state: State?
    }
    public struct Snapshot: Codable {
        public let started: Date?, expires: Date?, recording: Bool, droppedEntries: Int, entries: [Entry]
    }
    private let lock = NSLock()
    private let capacity: Int
    private var entries = [Entry]()
    private var next = 0, dropped = 0
    private var started: Date?, expires: Date?
    private var enabled = false
    public init(capacity: Int = 5000) { self.capacity = max(1, min(5000, capacity)) }
    public func start(now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll(keepingCapacity: true); next = 0; dropped = 0
        started = now; expires = now.addingTimeInterval(15 * 60); enabled = true
        append(Entry(time: now, event: .started, terminal: nil, sequence: nil, byteCount: 0,
                     input: .none, modifiers: 0, repeated: false, state: nil))
    }
    public func stop(now: Date = Date()) {
        record(.stopped, now: now)
        lock.lock(); enabled = false; lock.unlock()
    }
    public func clear() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll(); next = 0; dropped = 0; started = nil; expires = nil; enabled = false
    }
    public func isRecording(now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return enabled && now < (expires ?? .distantPast)
    }
    public func record(_ event: Event, terminal: UUID? = nil, sequence: Int? = nil, byteCount: Int = 0,
                       input: InputKind = .none, modifiers: UInt = 0, repeated: Bool = false,
                       state: State? = nil, now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        guard enabled, now < (expires ?? .distantPast) else { return }
        append(Entry(time: now, event: event, terminal: terminal, sequence: sequence, byteCount: max(0, byteCount),
                     input: input, modifiers: modifiers, repeated: repeated, state: state))
    }
    private func append(_ entry: Entry) {
        if entries.count < capacity { entries.append(entry) }
        else { entries[next] = entry; next = (next + 1) % capacity; dropped += 1 }
    }
    public func snapshot(now: Date = Date()) -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        let ordered = next == 0 ? entries : Array(entries[next...]) + Array(entries[..<next])
        return Snapshot(started: started, expires: expires, recording: enabled && now < (expires ?? .distantPast), droppedEntries: dropped, entries: ordered)
    }
}
