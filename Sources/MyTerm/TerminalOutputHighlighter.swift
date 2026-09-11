import Foundation
import SwiftTerm
import MyTermCore

/// Maps decoded graphemes back to terminal columns; never writes cells or protocol bytes.
final class TerminalOutputHighlighter {
    let configuration: OutputHighlightConfiguration
    private let matcher: OutputHighlightMatcher
    private struct Cache {
        var lines: [BufferLine]
        var generations: [UInt64]
        var columns: Int
        var colors: [[Int: Attribute.Color]]
    }
    private var cache: [ObjectIdentifier: Cache] = [:]
    init(_ configuration: OutputHighlightConfiguration) throws {
        self.configuration = configuration
        matcher = try OutputHighlightMatcher(configuration)
    }
    func colors(terminal: Terminal, row: Int, line: BufferLine, columns: Int, isSSH: Bool) -> [Int: Attribute.Color] {
        guard configuration.enabled, isSSH || configuration.includeLocal,
              !terminal.isCurrentBufferAlternate || configuration.includeAlternate else { return [:] }
        var start = row
        while let previous = terminal.bufferLine(atRow: start), previous.isWrapped, start > 0 {
            start -= 1
            if row - start >= 128 { return [:] }
        }
        var lines: [BufferLine] = []
        for index in start..<(start + 128) {
            guard let candidate = terminal.bufferLine(atRow: index) else { break }
            if index != start && !candidate.isWrapped { break }
            lines.append(candidate)
        }
        guard let first = lines.first, lines.indices.contains(row - start), lines[row - start] === line else { return [:] }
        if let after = terminal.bufferLine(atRow: start + lines.count), after.isWrapped { return [:] }
        let key = ObjectIdentifier(first), generations = lines.map(\.generation)
        if let entry = cache[key], entry.columns == columns, entry.generations == generations,
           entry.lines.count == lines.count, zip(entry.lines, lines).allSatisfy({ $0.0 === $0.1 }) {
            return entry.colors[row - start]
        }
        var text = "", cells: [(line: Int, column: Int, range: NSRange)] = [], offset = 0
        for (lineIndex, bufferLine) in lines.enumerated() {
            for col in 0..<min(columns, bufferLine.count) {
                let cell = bufferLine[col]
                guard cell.width != 0 else { continue }
                let character = terminal.getCharacter(for: cell)
                let value = character == "\0" ? " " : String(character)
                let length = value.utf16.count
                cells.append((lineIndex, col, NSRange(location: offset, length: length)))
                text += value; offset += length
            }
            if offset > 16384 { return [:] }
        }
        var colors = Array(repeating: [Int: Attribute.Color](), count: lines.count)
        for match in matcher.matches(in: text) {
            for cell in cells where NSIntersectionRange(cell.range, match.range).length > 0 {
                let attr = lines[cell.line][cell.column].attribute
                // Preserve special visual semantics even when ANSI color preservation is disabled.
                guard !attr.style.contains(.inverse), !attr.style.contains(.invisible) else { continue }
                if configuration.preserveANSI && attr.fg != .defaultColor { continue }
                colors[cell.line][cell.column] = .trueColor(red: match.color.red, green: match.color.green, blue: match.color.blue)
            }
        }
        if cache.count >= 256 { cache.removeAll(keepingCapacity: true) }
        cache[key] = Cache(lines: lines, generations: generations, columns: columns, colors: colors)
        return colors[row - start]
    }
}
