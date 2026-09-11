import Foundation

/// Accumulate finger travel, discard momentum, and cap each update at half a point.
struct FontZoomGesture {
    private var travel = 0.0
    private var lastStep = -Double.infinity
    private var lastEvent = -Double.infinity
    private var zooming = false

    // nil means ordinary scrolling; zero consumes the event without changing size.
    mutating func consume(delta: Double, inverted: Bool, precise: Bool, control: Bool,
                          momentum: Bool, began: Bool, timestamp: Double) -> Double? {
        if began || timestamp - lastEvent > 0.4 { travel = 0; zooming = false }
        lastEvent = timestamp
        if momentum { return control || zooming ? 0 : nil }
        guard control else { travel = 0; zooming = false; return nil }
        zooming = true
        guard delta.isFinite else { return 0 }
        let movement = (inverted ? -delta : delta) * (precise ? 1 : 10)
        if movement * travel < 0 { travel = 0 }
        travel += movement
        guard abs(travel) >= 40, timestamp - lastStep >= 0.15 else { return 0 }
        let step = travel > 0 ? 0.5 : -0.5
        travel = 0; lastStep = timestamp
        return step
    }
}
