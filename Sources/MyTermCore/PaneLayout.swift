import Foundation

public enum PaneAxis: String, Codable, CaseIterable {
    case horizontal, vertical
    public var title: String { self == .horizontal ? "上下分屏" : "左右分屏" }
}

/// Leaves reference existing sessions. Layout edits never own or restart processes.
public indirect enum PaneLayout: Codable, Equatable, Identifiable {
    case leaf(UUID)
    case split(UUID, PaneAxis, PaneLayout, PaneLayout)
    public var id: UUID {
        switch self { case .leaf(let id), .split(let id, _, _, _): return id }
    }
    public var nodeIDs: [UUID] {
        switch self { case .leaf(let id): return [id]; case .split(let id, _, let a, let b): return [id] + a.nodeIDs + b.nodeIDs }
    }
    public var leaves: [UUID] {
        switch self { case .leaf(let id): return [id]; case .split(_, _, let a, let b): return a.leaves + b.leaves }
    }
    public func remapping(_ ids: [UUID: UUID]) -> PaneLayout? {
        switch self {
        case .leaf(let id): return ids[id].map { .leaf($0) }
        case .split(_, let axis, let a, let b):
            guard let first = a.remapping(ids), let second = b.remapping(ids) else { return nil }
            return .split(UUID(), axis, first, second)
        }
    }
    public func inserting(_ newID: UUID, beside target: UUID, axis: PaneAxis) -> PaneLayout {
        switch self {
        case .leaf(let id): return id == target ? .split(UUID(), axis, self, .leaf(newID)) : self
        case .split(let id, let direction, let a, let b):
            return .split(id, direction, a.inserting(newID, beside: target, axis: axis), b.inserting(newID, beside: target, axis: axis))
        }
    }
    public func removing(_ target: UUID) -> PaneLayout? {
        switch self {
        case .leaf(let id): return id == target ? nil : self
        case .split(let id, let axis, let a, let b):
            switch (a.removing(target), b.removing(target)) {
            case (let a?, let b?): return .split(id, axis, a, b)
            case (let remaining?, nil), (nil, let remaining?): return remaining
            case (nil, nil): return nil
            }
        }
    }
}
