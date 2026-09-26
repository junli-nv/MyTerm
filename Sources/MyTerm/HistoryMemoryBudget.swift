import Foundation
import SwiftTerm
import Combine
import MyTermCore

/// One application-wide budget shared by live and retained terminal tabs.
/// Changes run on the UI queue. Width only grows during a tab's lifetime because
/// old scrollback can retain wider rows after the window becomes narrower.
final class HistoryMemoryBudget {
    static let shared = HistoryMemoryBudget()
    private final class Entry {
        weak var terminal: MouseTerminalView?
        var widestColumns: Int
        init(_ terminal: MouseTerminalView) {
            self.terminal = terminal
            widestColumns = terminal.getTerminal().cols
        }
    }
    private var entries: [UUID: Entry] = [:]
    private var subscriptions = Set<AnyCancellable>()
    private var maximumLines = 50_000
    private var budgetMiB = 256

    private init() {
        let preferences = HistoryPreferences.shared
        preferences.$policy.sink { [weak self] policy in
            guard (try? policy.validate()) != nil else { return }
            self?.maximumLines = policy.maximumLines
            self?.rebalance()
        }.store(in: &subscriptions)
        preferences.$memoryBudgetMiB.sink { [weak self] value in
            guard HistoryPreferences.validMemoryBudget(value) else { return }
            self?.budgetMiB = value
            self?.rebalance()
        }.store(in: &subscriptions)
    }

    func register(_ terminal: MouseTerminalView, id: UUID) {
        entries[id] = Entry(terminal)
        rebalance()
    }
    func remove(_ id: UUID) {
        entries[id] = nil
        rebalance()
    }
    func resized(_ id: UUID, columns: Int) {
        guard let entry = entries[id], columns > entry.widestColumns else { return }
        entry.widestColumns = columns
        rebalance()
    }
    private func rebalance() {
        entries = entries.filter { $0.value.terminal != nil }
        for entry in entries.values {
            guard let view = entry.terminal else { continue }
            let terminal = view.getTerminal()
            let limit = TerminalHistoryBudget.lineLimit(budgetMiB: budgetMiB,
                sessionCount: entries.count, widestColumns: entry.widestColumns,
                cellBytes: MemoryLayout<CharData>.stride, maximumLines: maximumLines)
            if terminal.options.scrollback != limit {
                view.selection.selectNone()
                terminal.changeScrollback(limit)
            }
        }
    }
}
