import AppKit
import SwiftUI
import MyTermCore

/// Real SFTP server, native table selection, file promises and shared-window lifecycle.
/// Temporary files only; no network login or user configuration changes.
enum SFTPInteractionCheck {
    static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-sftp-ui-\(UUID())")
        let remote = root.appendingPathComponent("remote"), local = root.appendingPathComponent("local")
        let fm = FileManager.default
        try fm.createDirectory(at: remote, withIntermediateDirectories: true)
        try fm.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let server = Server(host: "sftp-ui.invalid"), context = try SSHLaunchContext(server: Server(host: "sftp-ui.invalid"))
        // The toolbar must exist before asynchronous SSH setup has supplied a model.
        let preparing = TerminalSession(label: "Preparing SSH", executable: "/usr/bin/ssh", arguments: [], server: server)
        let toolbar = NSHostingView(rootView: TerminalSFTPButton(session: preparing))
        toolbar.frame = NSRect(x: 0, y: 0, width: 32, height: 28)
        toolbar.layoutSubtreeIfNeeded()
        func toolbarButtons(_ root: NSView) -> [NSButton] {
            (root as? NSButton).map { [$0] } ?? root.subviews.flatMap(toolbarButtons)
        }
        guard preparing.sftp == nil, let shortcut = toolbarButtons(toolbar).first(where: { $0.identifier?.rawValue == "tabbar.sftp" }) else {
            throw ConfigurationError.invalid("SFTP shortcut missing before async SSH setup")
        }
        shortcut.performClick(nil)
        guard preparing.showSFTP && !preparing.statusBarVisible else {
            throw ConfigurationError.invalid("SFTP shortcut requires the bottom status bar")
        }
        var activeClient: SFTPClient?
        let model = SFTPModel(server: server, context: context) {
            let client = SFTPClient(executable: "/usr/libexec/sftp-server", arguments: ["-d", remote.path])
            activeClient = client
            return client
        }
        defer { model.stop() }
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw ConfigurationError.invalid("SFTP check: " + message) }
        }
        func wait(line: Int = #line, _ predicate: () -> Bool) throws {
            let deadline = Date().addingTimeInterval(5)
            while !predicate() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            try require(predicate(), "operation timed out at line \(line): " + model.status)
        }
        let files = [local.appendingPathComponent("中文 one.txt"), local.appendingPathComponent("two.txt")]
        for (index, file) in files.enumerated() { try Data(repeating: UInt8(index + 1), count: 100_000).write(to: file) }
        model.connect(); try wait { !model.busy }
        try require(model.connected, "connect failed")
        model.upload(files); try wait { !model.busy }
        try require(model.entries.count == 2 && model.connected, "batch upload failed: " + model.status)
        for file in files { try require(try Data(contentsOf: file) == Data(contentsOf: remote.appendingPathComponent(file.lastPathComponent)), "uploaded bytes differ") }

        var prompts = 0
        func oldRemote() throws { for file in files { try Data("old".utf8).write(to: remote.appendingPathComponent(file.lastPathComponent)) } }
        try oldRemote()
        model.uploadConflictHandler = { _, _, allowed in
            prompts += 1; return allowed && prompts == 2 ? .overwrite : .skip
        }
        model.upload(files); try wait { !model.busy }
        try require(model.connected && prompts == 2, "mixed conflict choices disconnected")
        try require(try Data(contentsOf: remote.appendingPathComponent(files[0].lastPathComponent)) == Data("old".utf8), "skip changed destination")
        try require(try Data(contentsOf: remote.appendingPathComponent(files[1].lastPathComponent)) == Data(contentsOf: files[1]), "overwrite failed")
        prompts = 0
        model.uploadConflictHandler = { _, _, _ in prompts += 1; return .overwriteAll }
        model.upload(files); try wait { !model.busy }
        try require(model.connected && prompts == 1, "overwrite-all prompted more than once")
        try oldRemote(); prompts = 0
        model.uploadConflictHandler = { _, _, _ in prompts += 1; return .skipAll }
        model.upload(files); try wait { !model.busy }
        try require(model.connected && prompts == 1, "skip-all failed")
        for file in files { try require(try Data(contentsOf: remote.appendingPathComponent(file.lastPathComponent)) == Data("old".utf8), "skip-all replaced content") }
        prompts = 0
        model.uploadConflictHandler = { _, _, _ in prompts += 1; return .cancel }
        model.upload(files); try wait { !model.busy }
        try require(model.connected && prompts == 1, "cancel conflict closed connection or batch policy leaked")
        model.navigate(remote.appendingPathComponent("missing").path); try wait { !model.busy }
        try require(model.connected, "missing directory disconnected SFTP")
        model.uploadConflictHandler = { _, _, _ in .overwriteAll }
        model.upload(files); try wait { !model.busy }
        try require(model.connected, "upload after conflict failed")

        let host = NSHostingView(rootView: SFTPFileTable(model: model))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 280), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        host.layoutSubtreeIfNeeded()
        guard let table = descendants(host).compactMap({ $0 as? SFTPTableView }).first,
              let coordinator = table.delegate as? SFTPFileTable.Coordinator else {
            throw ConfigurationError.invalid("SFTP native table missing")
        }
        // SwiftUI publication and AppKit activation are asynchronous. Wait for
        // observable readiness instead of assuming a 100 ms delay is sufficient.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try wait {
            host.layoutSubtreeIfNeeded()
            return window.isKeyWindow && coordinator.entries == model.entries
                && table.numberOfRows == files.count && table.visibleRect.height > table.rowHeight
        }
        func click(_ row: Int, flags: NSEvent.ModifierFlags = []) {
            let rect = table.rect(ofRow: row)
            let point = table.convert(NSPoint(x: 50, y: rect.midY), to: nil)
            let now = ProcessInfo.processInfo.systemUptime
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: flags, timestamp: now, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: flags, timestamp: now + 0.01, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
            NSApp.postEvent(up, atStart: true); window.sendEvent(down)
        }
        click(0); try require(model.selected.count == 1, "single click did not select file")
        click(1, flags: .command); try require(model.selected.count == 2, "Command-click failed")
        click(0); click(1, flags: .shift); try require(model.selected.count == 2, "Shift-click failed")
        let point = table.convert(NSPoint(x: 30, y: table.rect(ofRow: 0).midY), to: nil)
        let right = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 1)!
        let menu = table.menu(for: right)
        try require(model.selected.count == 2 && menu?.items.first?.isEnabled == true, "context menu lost batch selection")

        let destinations = files.map { local.appendingPathComponent("download-" + $0.lastPathComponent) }
        model.download(model.selectedEntries, destinations: destinations); try wait { !model.busy }
        for (entry, destination) in zip(model.selectedEntries, destinations) {
            try require(try Data(contentsOf: destination) == Data(contentsOf: remote.appendingPathComponent(entry.name)), "batch download bytes differ")
        }
        let dragDirectory = root.appendingPathComponent("promises")
        try fm.createDirectory(at: dragDirectory, withIntermediateDirectories: true)
        let promises = (0..<2).compactMap { coordinator.tableView(table, pasteboardWriterForRow: $0) as? NSFilePromiseProvider }
        try require(promises.count == 2, "file promises unavailable")
        var completed = 0, errors = [Error]()
        for promise in promises {
            guard let delegate = promise.delegate else { throw ConfigurationError.invalid("Missing promise delegate") }
            let name = delegate.filePromiseProvider(promise, fileNameForType: promise.fileType)
            delegate.filePromiseProvider(promise, writePromiseTo: dragDirectory.appendingPathComponent(name)) { error in
                completed += 1; if let error { errors.append(error) }
            }
        }
        try wait { completed == 2 }
        try require(errors.isEmpty && !model.busy, "promised downloads failed")
        for entry in model.entries { try require(try Data(contentsOf: dragDirectory.appendingPathComponent(entry.name)) == Data(contentsOf: remote.appendingPathComponent(entry.name)), "promised bytes differ") }
        // Existing promise destinations use the same conflict path as button downloads.
        var downloadPrompts = 0
        model.downloadConflictHandler = { _, _, allowed in downloadPrompts += 1; return allowed ? .overwrite : .cancel }
        try Data("old local".utf8).write(to: dragDirectory.appendingPathComponent(files[0].lastPathComponent))
        var replaced = false
        model.downloadPromise(remote: remote.appendingPathComponent(files[0].lastPathComponent).path,
            destination: dragDirectory.appendingPathComponent(files[0].lastPathComponent), connectionID: model.connectionID) { error in
            replaced = error == nil
        }
        try wait { !model.busy }
        try require(replaced && downloadPrompts == 1 && model.connected, "download overwrite failed or disconnected")
        try require(try Data(contentsOf: dragDirectory.appendingPathComponent(files[0].lastPathComponent)) == Data(contentsOf: files[0]), "download overwrite bytes differ")
        let downloadEntries = model.entries.filter { !$0.isDirectory }
        let downloadTargets = downloadEntries.map { dragDirectory.appendingPathComponent($0.name) }
        for target in downloadTargets { try Data("preserve local".utf8).write(to: target) }
        downloadPrompts = 0
        model.downloadConflictHandler = { _, _, _ in downloadPrompts += 1; return .skipAll }
        model.download(downloadEntries, destinations: downloadTargets); try wait { !model.busy }
        try require(downloadPrompts == 1 && model.connected, "download skip-all did not remain batch scoped")
        for target in downloadTargets { try require(try Data(contentsOf: target) == Data("preserve local".utf8), "download skip changed original") }
        downloadPrompts = 0
        model.downloadConflictHandler = { _, _, _ in downloadPrompts += 1; return .overwriteAll }
        model.download(downloadEntries, destinations: downloadTargets); try wait { !model.busy }
        try require(downloadPrompts == 1 && model.connected, "download overwrite-all failed")
        for target in downloadTargets { try require(try Data(contentsOf: target) == Data(contentsOf: remote.appendingPathComponent(target.lastPathComponent)), "batch overwrite bytes differ") }
        model.downloadConflictHandler = { _, _, _ in .cancel }
        model.download(downloadEntries, destinations: downloadTargets); try wait { !model.busy }
        try require(model.connected, "cancelling a download conflict disconnected SFTP")
        model.downloadConflictHandler = { _, _, allowed in allowed ? .overwrite : .skip }
        let uploadFolder = local.appendingPathComponent("tree")
        try fm.createDirectory(at: uploadFolder.appendingPathComponent("nested/empty"), withIntermediateDirectories: true)
        try Data("recursive drag".utf8).write(to: uploadFolder.appendingPathComponent("nested/test.txt"))
        model.upload([uploadFolder]); try wait { !model.busy }
        try Data("nested old".utf8).write(to: remote.appendingPathComponent("tree/nested/test.txt"))
        model.upload([uploadFolder]); try wait { !model.busy }
        try require(model.connected && (try? Data(contentsOf: remote.appendingPathComponent("tree/nested/test.txt"))) == Data("recursive drag".utf8), "recursive overwrite failed")
        try wait { coordinator.entries.contains(where: { $0.name == "tree" }) }
        guard let directoryIndex = coordinator.entries.firstIndex(where: { $0.name == "tree" }),
              let folderPromise = coordinator.tableView(table, pasteboardWriterForRow: directoryIndex) as? NSFilePromiseProvider,
              let folderWriter = folderPromise.delegate else { throw ConfigurationError.invalid("Directory drag promise missing") }
        var folderDone = false, folderError: Error?
        folderWriter.filePromiseProvider(folderPromise, writePromiseTo: dragDirectory.appendingPathComponent("tree")) { error in
            folderError = error; folderDone = true
        }
        try wait { folderDone }
        try require(folderError == nil, "directory promise failed")
        try require(try Data(contentsOf: dragDirectory.appendingPathComponent("tree/nested/test.txt")) == Data("recursive drag".utf8), "directory drag bytes differ")
        try require(fm.fileExists(atPath: dragDirectory.appendingPathComponent("tree/nested/empty").path), "empty directory was lost")
        // Finder queues multiple promises before their worker completions reach
        // the main queue. A fatal first task closes the transport; later files
        // and directories must report errors, never touch closed FileHandles.
        activeClient?.cancel()
        var failedPromises = 0, unexpectedSuccesses = 0
        let failedNames = [files[0].lastPathComponent, files[1].lastPathComponent, "tree"]
        for (index, name) in failedNames.enumerated() {
            model.downloadPromise(remote: remote.appendingPathComponent(name).path,
                                  destination: local.appendingPathComponent("failed-promise-\(index)"),
                                  connectionID: model.connectionID) { error in
                failedPromises += 1
                if error == nil { unexpectedSuccesses += 1 }
            }
        }
        try wait { failedPromises == failedNames.count }
        try require(unexpectedSuccesses == 0 && !model.connected && !model.busy,
                    "Failed promise batch left a live/stuck connection")
        try require(failedNames.indices.allSatisfy { !fm.fileExists(atPath: local.appendingPathComponent("failed-promise-\($0)").path) },
                    "Queued promises created destinations after transport failure")
        model.connect(); try wait { !model.busy }
        try require(model.connected, "Reconnect after failed promise batch failed")
        print("PASS: failed queued file/directory promises complete without closed-handle access; reconnect succeeds")
        model.showWindow(); try require(model.detached && model.connected, "detaching lost connection")
        model.dock(); try require(!model.detached && model.connected, "docking lost connection")
        let previousID = model.connectionID
        model.disconnect(); try require(!model.connected && !model.busy && model.selected.isEmpty, "disconnect left stale state")
        model.connect(); try wait { !model.busy }
        var refused = false
        model.downloadPromise(remote: remote.appendingPathComponent(files[0].lastPathComponent).path, destination: local.appendingPathComponent("stale.txt"), connectionID: previousID) { refused = $0 != nil }
        try require(refused && model.connected, "stale drag reused a reconnected client")
        model.upload(files); model.cancel(); try require(!model.connected && !model.busy, "cancel failed")
        model.connect(); try wait { !model.busy }
        try require(model.connected, "reconnect after cancellation failed")
        let language = LanguagePreferences.shared, originalLanguage = LanguagePreferences.shared.selection
        defer { language.selection = originalLanguage }
        for selection in [InterfaceLanguage.chinese, .english] {
            language.selection = selection
            let panel = NSHostingView(rootView: SFTPPanel(model: model).frame(width: 360))
            panel.frame = NSRect(x: 0, y: 0, width: 360, height: 460)
            panel.layoutSubtreeIfNeeded()
            try require(panel.fittingSize.width <= 361, "bilingual panel exceeded minimum width")
        }
        let folder = remote.appendingPathComponent("folder")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        model.navigate(remote.path); try wait { !model.busy }
        guard let directoryEntry = model.entries.first(where: { $0.isDirectory }) else {
            throw ConfigurationError.invalid("SFTP directory missing")
        }
        model.open(directoryEntry); try wait { !model.busy }
        try require(URL(fileURLWithPath: model.path).resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path, "directory navigation failed: \(model.path) / \(folder.path), \(model.status)")
        print("PASS: SFTP real server batch upload/download, native single/Command/Shift selection, context menu, multi-file promises, detach/dock, disconnect, stale drag and cancellation")
    }
}
