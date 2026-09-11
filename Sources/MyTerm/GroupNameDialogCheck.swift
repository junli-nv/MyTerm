#if DEBUG
import AppKit
import MyTermCore

enum GroupNameDialogCheck {
    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MyTerm-group-dialog-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = SessionGroupRepository(url: directory.appendingPathComponent("groups.json"))
        let dialog = GroupNameDialog(name: nil)
        var step = 0
        var inputFailed = false
        let timer = Timer(timeInterval: 0.1, repeats: true) { timer in
            step += 1
            guard step <= 3 else { timer.invalidate(); NSApp.abortModal(); return }
            dialog.alert.window.makeFirstResponder(dialog.field)
            guard let editor = dialog.field.currentEditor() as? NSTextView else {
                inputFailed = true; timer.invalidate(); NSApp.abortModal(); return
            }
            // Submit invalid text, then correct it without leaving the dialog.
            editor.insertText(step == 1 ? "   " : "  生产环境  ", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            dialog.alert.buttons[0].performClick(nil)
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        dialog.run { try repository.save([SessionGroup(name: $0)]) }
        timer.invalidate()
        guard !inputFailed, step == 2, try repository.load().map(\.name) == ["生产环境"] else {
            throw ConfigurationError.invalid("Group dialog failed to retry and save active Chinese input")
        }
        let cancel = GroupNameDialog(name: "生产环境")
        var saved = false
        let cancelTimer = Timer(timeInterval: 0.1, repeats: false) { _ in cancel.alert.buttons[1].performClick(nil) }
        RunLoop.main.add(cancelTimer, forMode: .modalPanel)
        cancel.run { _ in saved = true }
        cancelTimer.invalidate()
        guard !saved else { throw ConfigurationError.invalid("Cancelling a group edit must not save") }
        print("PASS: group dialog accepts Chinese input, retries invalid names, persists trimmed text and cancels without saving")
        for (input, expected, marked) in [("\u{200B}生产\u{0000}环境\u{FEFF}", "生产环境", false),
                                           ("测试\t服务器\r\n", "测试 服务器", false),
                                           ("中文输入法", "中文输入法", true),
                                           (String(repeating: "中", count: 60), String(repeating: "中", count: 60), false)] {
            let inputDialog = GroupNameDialog(name: "旧名称")
            var attempts = 0
            let inputTimer = Timer(timeInterval: 0.1, repeats: true) { timer in
                attempts += 1
                guard attempts == 1 else { timer.invalidate(); NSApp.abortModal(); return }
                inputDialog.alert.window.makeFirstResponder(inputDialog.field)
                guard let editor = inputDialog.field.currentEditor() as? NSTextView else { NSApp.abortModal(); return }
                let range = NSRange(location: 0, length: editor.string.utf16.count)
                if marked {
                    editor.setMarkedText(input, selectedRange: NSRange(location: input.utf16.count, length: 0), replacementRange: range)
                } else { editor.insertText(input, replacementRange: range) }
                inputDialog.alert.buttons[0].performClick(nil)
            }
            RunLoop.main.add(inputTimer, forMode: .modalPanel)
            var savedName: String?
            inputDialog.run { name in
                try repository.save([SessionGroup(name: name)])
                savedName = name
            }
            inputTimer.invalidate()
            guard attempts == 1, savedName == expected, try repository.load().first?.name == expected else {
                throw ConfigurationError.invalid("Group dialog failed invisible-character, multiline, IME or 60-character input regression")
            }
        }
        print("PASS: real group dialogs save invisible-character input, pasted line separators, active IME marked text and 60-character names")
        let workflowRoot = directory.appendingPathComponent("workflow")
        let workflow = Workspace(applicationSupportDirectory: workflowRoot)
        func editInWorkspace(_ group: SessionGroup?, name: String) throws {
            var attempts = 0
            func inputField(in view: NSView) -> NSTextField? {
                if let field = view as? NSTextField, field.isEditable { return field }
                return view.subviews.lazy.compactMap { inputField(in: $0) }.first
            }
            func saveButton(in view: NSView) -> NSButton? {
                if let button = view as? NSButton, button.title == L10n.text("保存") { return button }
                return view.subviews.lazy.compactMap { saveButton(in: $0) }.first
            }
            let timer = Timer(timeInterval: 0.1, repeats: true) { timer in
                attempts += 1
                guard attempts == 1, let window = NSApp.modalWindow, let content = window.contentView,
                      let field = inputField(in: content), let button = saveButton(in: content) else {
                    timer.invalidate(); NSApp.abortModal(); return
                }
                window.makeFirstResponder(field)
                guard let editor = field.currentEditor() as? NSTextView else { NSApp.abortModal(); return }
                editor.insertText(name, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
                button.performClick(nil)
            }
            RunLoop.main.add(timer, forMode: .modalPanel)
            workflow.editGroup(group)
            timer.invalidate()
            guard attempts == 1, workflow.error == nil, workflow.groups.last?.name == SessionGroup.normalizedName(name) else {
                throw ConfigurationError.invalid("Actual Workspace group creation/rename failed")
            }
        }
        try editInWorkspace(nil, name: "\u{200B}生产环境")
        try editInWorkspace(workflow.groups[0], name: "重新命名")
        let reopened = Workspace(applicationSupportDirectory: workflowRoot)
        guard reopened.groups == workflow.groups, !reopened.groupRecoveryRequired, reopened.error == nil else {
            throw ConfigurationError.invalid("Groups created through the real workspace must reload without alerts")
        }
        print("PASS: actual Workspace new-group and rename dialogs persist and reload without a recovery notice")
        let workspace = Workspace(applicationSupportDirectory: directory)
        let startupGroups = directory.appendingPathComponent("MyTerm/groups.json")
        try FileManager.default.createDirectory(at: startupGroups.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("broken group file".utf8).write(to: startupGroups)
        let recoveredWorkspace = Workspace(applicationSupportDirectory: directory)
        guard recoveredWorkspace.groups.isEmpty, recoveredWorkspace.error == nil,
              Workspace(applicationSupportDirectory: directory).error == nil else {
            throw ConfigurationError.invalid("Optional groups must not cause repeated startup alerts")
        }
        _ = try recoveredWorkspace.backupConfigurationFiles()
        guard recoveredWorkspace.groupRecoveryRequired else { throw ConfigurationError.invalid("Damaged groups must offer repair/remove actions") }
        recoveredWorkspace.repairGroupFile()
        guard !recoveredWorkspace.groupRecoveryRequired, !Workspace(applicationSupportDirectory: directory).groupRecoveryRequired else {
            throw ConfigurationError.invalid("Repair must persist and clear the recovery notice on restart")
        }
        try Data("broken again".utf8).write(to: startupGroups)
        let removalWorkspace = Workspace(applicationSupportDirectory: directory)
        let retained = Server(host: "retained.example.invalid")
        removalWorkspace.servers = [retained]
        removalWorkspace.removeGroupFile()
        guard !removalWorkspace.groupRecoveryRequired, removalWorkspace.groups.isEmpty,
              removalWorkspace.servers == [retained], !FileManager.default.fileExists(atPath: startupGroups.path),
              !Workspace(applicationSupportDirectory: directory).groupRecoveryRequired else {
            throw ConfigurationError.invalid("Removing damaged groups must retain servers and clear the notice on restart")
        }
        print("PASS: damaged group repair/removal preserves servers and clears the recovery notice across restarts")
        print("PASS: damaged optional group file does not block startup or backup and does not repeat alerts")
        let server = Server(name: "拖拽测试", host: "example.invalid")
        workspace.servers = [server]
        workspace.groups = [SessionGroup(name: "生产"), SessionGroup(name: "测试", collapsed: true)]
        let payload = try JSONDecoder().decode(SavedServerDrag.self, from: JSONEncoder().encode(SavedServerDrag(id: server.id)))
        guard workspace.moveDraggedServers([payload.id], to: workspace.groups[0].id),
              workspace.moveDraggedServers([payload.id], to: workspace.groups[1].id),
              workspace.groups[0].serverIDs.isEmpty,
              workspace.groups[1].serverIDs == [server.id] else {
            throw ConfigurationError.invalid("Dragging must move a server between groups, including collapsed groups")
        }
        let persisted = SessionGroupRepository(url: directory.appendingPathComponent("MyTerm/groups.json"))
        guard try persisted.load() == workspace.groups,
              !workspace.moveDraggedServers([UUID()], to: nil),
              !workspace.moveDraggedServers([server.id], to: UUID()),
              workspace.moveDraggedServers([server.id], to: nil),
              try persisted.load().flatMap(\.serverIDs).isEmpty,
              workspace.servers == [server], workspace.sessions.isEmpty else {
            throw ConfigurationError.invalid("Ungrouping must persist without deleting or connecting the server; invalid drops must be rejected")
        }
        print("PASS: group drag payload, move between groups, ungroup, persistence and invalid drops")
        guard (Bundle.main.infoDictionary?["UTExportedTypeDeclarations"] as? [[String: Any]])?.contains(where: {
                  $0["UTTypeIdentifier"] as? String == SavedServerDrag.typeIdentifier
              }) == true else { throw ConfigurationError.invalid("Drag type must be declared in the application bundle") }
        func drop(_ provider: NSItemProvider, into groupID: UUID?) throws -> Bool {
            var result: Bool?
            guard SavedServerDrag.receive([provider], workspace: workspace, groupID: groupID, completion: { result = $0 }) else { return false }
            let deadline = Date().addingTimeInterval(3)
            while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            guard let result else { throw ConfigurationError.invalid("Timed out reading the actual drag item provider") }
            return result
        }
        guard try drop(SavedServerDrag(id: server.id).itemProvider, into: workspace.groups[0].id),
              workspace.groups[0].serverIDs == [server.id],
              try drop(SavedServerDrag(id: server.id).itemProvider, into: workspace.groups[1].id),
              workspace.groups[0].serverIDs.isEmpty,
              workspace.groups[1].serverIDs == [server.id],
              try drop(SavedServerDrag(id: server.id).itemProvider, into: nil),
              try persisted.load().flatMap(\.serverIDs).isEmpty,
              try !drop(NSItemProvider(object: "unrelated text" as NSString), into: workspace.groups[0].id),
              try !drop(SavedServerDrag(id: UUID()).itemProvider, into: workspace.groups[0].id) else {
            throw ConfigurationError.invalid("Native item-provider group drop failed")
        }
        print("PASS: actual NSItemProvider drop delivery from ungrouped to group, between groups, back to ungrouped, and invalid drop rejection")
    }
}
#endif
