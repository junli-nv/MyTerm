import Foundation

/// A conservative capacity estimate for terminal character rows, not a limit on
/// total process memory (visible screens, images and UI objects are separate).
public enum TerminalHistoryBudget {
    public static func lineLimit(budgetMiB: Int, sessionCount: Int, widestColumns: Int,
                                 cellBytes: Int, maximumLines: Int) -> Int {
        guard budgetMiB > 0 else { return maximumLines }
        let share = budgetMiB * 1024 * 1024 / max(1, sessionCount)
        // Account for allocation rounding, line metadata and ring-list references.
        let rowBytes = ((max(1, widestColumns) * cellBytes + 4095) / 4096) * 4096 + 512
        return min(maximumLines, max(0, share / rowBytes))
    }
}
