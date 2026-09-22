import AppKit
import SwiftUI
import MyTermCore
import UniformTypeIdentifiers

/// Native selection owns click, range selection and dragging; no competing SwiftUI gestures.
struct SFTPFileTable: NSViewRepresentable {
    @ObservedObject var model: SFTPModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = SFTPTableView()
        for (id, title, width) in [("name", "名称", 230.0), ("size", "大小", 85.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = L10n.text(title); column.width = width
            column.minWidth = id == "name" ? 100 : 65
            table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.allowsMultipleSelection = true; table.allowsEmptySelection = true
        table.rowHeight = 26; table.usesAlternatingRowBackgroundColors = true
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.target = context.coordinator; table.doubleAction = #selector(Coordinator.openDirectory)
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        table.menu = NSMenu(); table.menu?.autoenablesItems = false
        table.contextDownload = { [weak coordinator = context.coordinator] in coordinator?.downloadMenu() ?? NSMenu() }
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = false; scroll.documentView = table
        context.coordinator.table = table
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.model = model
        guard let table = coordinator.table else { return }
        coordinator.updating = true
        defer { coordinator.updating = false }
        if coordinator.entries != model.entries {
            coordinator.entries = model.entries; table.reloadData()
        }
        table.tableColumns[0].title = L10n.text("名称")
        table.tableColumns[1].title = L10n.text("大小")
        let indexes = IndexSet(coordinator.entries.indices.filter { model.selected.contains(coordinator.entries[$0].name) })
        if table.selectedRowIndexes != indexes { table.selectRowIndexes(indexes, byExtendingSelection: false) }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var model: SFTPModel
        var entries: [RemoteEntry] = []
        weak var table: SFTPTableView?
        var updating = false
        init(model: SFTPModel) { self.model = model }
        func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard entries.indices.contains(row) else { return nil }
            let entry = entries[row]
            let text: String
            if tableColumn?.identifier.rawValue == "size" {
                text = entry.isDirectory ? "" : entry.size.map { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0), countStyle: .file) } ?? ""
            } else { text = (entry.isDirectory ? "📁 " : entry.isLink ? "↗ " : "") + entry.name }
            let field = NSTextField(labelWithString: text)
            field.lineBreakMode = .byTruncatingMiddle; field.toolTip = entry.name
            return field
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }
            model.selected = Set(table.selectedRowIndexes.compactMap { entries.indices.contains($0) ? entries[$0].name : nil })
        }
        @objc func openDirectory() {
            guard let row = table?.clickedRow, entries.indices.contains(row) else { return }
            model.open(entries[row])
        }
        @objc func downloadSelected() { model.download() }
        func downloadMenu() -> NSMenu {
            let menu = NSMenu(); menu.autoenablesItems = false
            let item = NSMenuItem(title: L10n.text("下载 / 续传…"), action: #selector(downloadSelected), keyEquivalent: "")
            item.target = self; item.isEnabled = model.connected && !model.busy && !model.selectedEntries.isEmpty
            menu.addItem(item); return menu
        }
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard model.connected, !model.busy, entries.indices.contains(row),
                  let remote = try? SFTPClient.joining(model.path, entries[row].name) else { return nil }
            return SFTPDownloadPromise.make(model: model, name: entries[row].name, remote: remote, directory: entries[row].isDirectory)
        }
        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
            guard model.connected, !model.busy, !Self.files(info).isEmpty else { return [] }
            tableView.setDropRow(-1, dropOperation: .on)
            return .copy
        }
        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            let files = Self.files(info)
            guard model.connected, !model.busy, !files.isEmpty else { return false }
            model.upload(files); return true
        }
        private static func files(_ info: NSDraggingInfo) -> [URL] {
            (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        }
    }
}

final class SFTPTableView: NSTableView {
    var contextDownload: (() -> NSMenu)?
    override func menu(for event: NSEvent) -> NSMenu? {
        let clicked = row(at: convert(event.locationInWindow, from: nil))
        guard clicked >= 0 else { return nil }
        // Right-clicking a selected row preserves the batch; another row becomes the selection.
        if !selectedRowIndexes.contains(clicked) { selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false) }
        return contextDownload?()
    }
}

/// Retain the promise delegate until Finder has received the file, including after drag-end.
private final class SFTPDownloadPromise: NSFilePromiseProvider {
    private var writer: Writer?
    static func make(model: SFTPModel, name: String, remote: String, directory: Bool) -> SFTPDownloadPromise {
        let writer = Writer(model: model, name: name, remote: remote)
        let provider = SFTPDownloadPromise(fileType: directory ? UTType.folder.identifier : UTType.data.identifier, delegate: writer)
        provider.writer = writer
        return provider
    }
    private final class Writer: NSObject, NSFilePromiseProviderDelegate {
        weak var model: SFTPModel?
        let name: String, remote: String
        let connectionID: UUID
        init(model: SFTPModel, name: String, remote: String) {
            self.model = model; self.name = name; self.remote = remote; connectionID = model.connectionID
        }
        func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { name }
        func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { .main }
        func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
            guard let model else { completionHandler(CancellationError()); return }
            model.downloadPromise(remote: remote, destination: url, connectionID: connectionID, completion: completionHandler)
        }
    }
}
