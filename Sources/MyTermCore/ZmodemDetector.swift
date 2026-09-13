import Foundation

public struct ZmodemDetection {
    public let visible: Data
    public let handshake: Data?
    public let receiving: Bool
}
public struct ZmodemDetector {
    private var pending = Data()
    // Printable protocol-prefix bytes are displayed immediately, but retained for
    // detection across reads. Never emit these bytes a second time on mismatch.
    private var displayed = 0
    private mutating func removeVisible(_ count: Int) -> Data {
        let visible = Data(pending.prefix(count).dropFirst(min(displayed, count)))
        pending = Data(pending.dropFirst(count))
        displayed = max(0, displayed - count)
        return visible
    }
    private mutating func displayStars() -> Data {
        let count = pending.prefix(while: { $0 == 42 }).count
        let visible = Data(pending.prefix(count).dropFirst(displayed))
        displayed = max(displayed, count)
        return visible
    }
    public init() {}
    public mutating func feed(_ data: Data) -> ZmodemDetection {
        pending.append(data)
        let marker = Data([42, 42, 24, 66])
        var visible = Data()
        while let range = pending.range(of: marker) {
            visible.append(removeVisible(range.lowerBound))
            if pending.count < 18 {
                visible.append(displayStars())
                return ZmodemDetection(visible: visible, handshake: nil, receiving: false)
            }
            let hex = pending.subdata(in: 4..<18)
            let valid = hex.allSatisfy { (48...57).contains($0) || (97...102).contains($0) || (65...70).contains($0) }
            let type = String(decoding: pending.subdata(in: 4..<6), as: UTF8.self)
            if valid && (type == "00" || type == "01") {
                let handshake = pending; pending = Data(); displayed = 0
                return ZmodemDetection(visible: visible, handshake: handshake, receiving: type == "00")
            }
            visible.append(removeVisible(1))
        }
        var held = 0
        for count in 1..<marker.count where pending.count >= count {
            if pending.suffix(count) == marker.prefix(count) { held = count }
        }
        visible.append(removeVisible(pending.count - held))
        visible.append(displayStars())
        return ZmodemDetection(visible: visible, handshake: nil, receiving: false)
    }
}
