import AppKit

/// The terminal protocol exposes alternate-screen state, not tmux copy-mode state.
/// Page navigation is therefore an explicit full-screen preference.
enum FullscreenScrollMode: String, CaseIterable {
    case standard, fast, pages
    var title: String {
        switch self {
        case .standard: return "标准滚动"
        case .fast: return "快速滚动"
        case .pages: return "按页翻动"
        }
    }
}

struct FullscreenScrollGesture {
    private var accumulated: CGFloat = 0
    private var lastPage: TimeInterval = -.infinity
    private var direction: CGFloat = 0
    mutating func reset() { self = Self() }

    /// One page per 48 points, at most every 180 ms. Momentum never sends keys.
    mutating func page(delta: CGFloat, began: Bool, momentum: Bool, timestamp: TimeInterval) -> Int {
        if began { reset() }
        if momentum { accumulated = 0; return 0 }
        guard delta != 0, delta.isFinite else { return 0 }
        let sign: CGFloat = delta > 0 ? 1 : -1
        if sign != direction { accumulated = 0; lastPage = -.infinity; direction = sign }
        accumulated = min(48, abs(accumulated + delta)) * sign
        guard abs(accumulated) >= 48, timestamp - lastPage >= 0.18 else { return 0 }
        accumulated = 0; lastPage = timestamp
        return delta > 0 ? 1 : -1
    }
}
