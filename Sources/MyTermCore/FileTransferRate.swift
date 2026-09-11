import Foundation

/// Rates use only bytes transferred after the initial resume offset.
public struct FileTransferRate {
    private var baseline: UInt64?
    private var started: TimeInterval = 0
    private var samples: [(TimeInterval, UInt64)] = []
    private(set) public var transferred: UInt64 = 0
    public init() {}
    public mutating func update(completed: UInt64, now: TimeInterval) {
        guard let baseline else {
            self.baseline = completed; started = now; samples = [(now, 0)]; return
        }
        transferred = max(transferred, completed >= baseline ? completed - baseline : 0)
    }
    public mutating func sample(now: TimeInterval) -> Double {
        guard baseline != nil else { return 0 }
        samples.append((now, transferred))
        while samples.count > 2, samples[1].0 <= now - 2 { samples.removeFirst() }
        return Double(transferred - samples[0].1) / max(0.001, now - samples[0].0)
    }
    public func average(now: TimeInterval) -> Double {
        guard baseline != nil else { return 0 }
        return Double(transferred) / max(0.001, now - started)
    }
}
