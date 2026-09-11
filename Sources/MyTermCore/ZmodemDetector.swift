import Foundation

public struct ZmodemDetection {
    public let visible: Data
    public let handshake: Data?
    public let receiving: Bool
}
public struct ZmodemDetector {
    private var pending = Data()
    public init() {}
    public mutating func feed(_ data: Data) -> ZmodemDetection {
        pending.append(data)
        let marker = Data([42, 42, 24, 66])
        var visible = Data()
        while let range = pending.range(of: marker) {
            visible.append(pending.prefix(upTo: range.lowerBound))
            pending = Data(pending.suffix(from: range.lowerBound))
            if pending.count < 18 { return ZmodemDetection(visible: visible, handshake: nil, receiving: false) }
            let hex = pending.subdata(in: 4..<18)
            let valid = hex.allSatisfy { (48...57).contains($0) || (97...102).contains($0) || (65...70).contains($0) }
            let type = String(decoding: pending.subdata(in: 4..<6), as: UTF8.self)
            if valid && (type == "00" || type == "01") {
                let handshake = pending; pending = Data()
                return ZmodemDetection(visible: visible, handshake: handshake, receiving: type == "00")
            }
            visible.append(pending.removeFirst())
            pending = Data(pending)
        }
        var held = 0
        for count in 1..<marker.count where pending.count >= count {
            if pending.suffix(count) == marker.prefix(count) { held = count }
        }
        visible.append(pending.prefix(pending.count - held)); pending = Data(pending.suffix(held))
        return ZmodemDetection(visible: visible, handshake: nil, receiving: false)
    }
}
