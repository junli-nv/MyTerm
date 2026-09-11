import Foundation

/// Two-second rolling throughput of the ZMODEM stream, including framing/retries.
struct ZmodemRateMeter {
    private let started: TimeInterval
    private var samples: [(time: TimeInterval, bytes: UInt64)]
    private(set) var bytes: UInt64 = 0
    init(now: TimeInterval) { started = now; samples = [(now, 0)] }
    mutating func add(_ count: Int) { bytes += UInt64(max(0, count)) }
    mutating func sample(now: TimeInterval) -> Double {
        samples.append((now, bytes))
        while samples.count > 2, samples[1].time <= now - 2 { samples.removeFirst() }
        let first = samples[0]
        return Double(bytes - first.bytes) / max(0.001, now - first.time)
    }
    func average(now: TimeInterval) -> Double { Double(bytes) / max(0.001, now - started) }
}
