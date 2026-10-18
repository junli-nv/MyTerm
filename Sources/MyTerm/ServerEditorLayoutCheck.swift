import AppKit
import SwiftUI
import MyTermCore

enum ServerEditorLayoutCheck {
    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("myterm-editor-check-\(UUID())")
        let workspace = Workspace(applicationSupportDirectory: directory)
        let controller = ServerEditorWindowController()
        let language = LanguagePreferences.shared, original = LanguagePreferences.shared.selection
        defer { controller.close(); language.selection = original; try? FileManager.default.removeItem(at: directory) }
        var server = Server(name: "Layout test", host: "example.com")
        server.proxy = NetworkProxy()
        server.jumpServers = [SSHJumpServer(host: "jump-one"), SSHJumpServer(host: "jump-two")]
        server.forwards = [PortForward(listenPort: "12345", destinationPort: "23456"),
                           PortForward(kind: .remote, listenPort: "12346", destinationPort: "23457"),
                           PortForward(kind: .dynamic, listenPort: "12347")]
        controller.present(server: server, workspace: workspace)
        let window = controller.window!, root = window.contentView!
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid("SSH editor layout: " + message) }
        }
        var keyed = server
        keyed.authentication = .key; keyed.identityFile = "/tmp/myterm-editor-key"
        keyed.jumpServers?[0].authentication = .key; keyed.jumpServers?[0].identityFile = "/tmp/myterm-editor-hop-key"
        try require(workspace.save(keyed), "Cannot save key fixture")
        let credentials = SQLitePasswordStore(directory: directory.appendingPathComponent("MyTerm/Credentials"))
        let oldAccount = try SSHPasswordMemory.legacyScopeIdentifier(for: keyed) + ":fixture"
        try credentials.save("fixture-only", account: oldAccount, label: "Fixture")
        let draft = ServerDraft(server: keyed)
        draft.server.name = "Edited key fixture"; draft.compression = false
        try require(workspace.save(draft.server), "Cannot save edited fixture")
        try require(workspace.servers.first?.identityFile == keyed.identityFile && workspace.servers.first?.authentication == .key,
                    "Editing discarded the private key or authentication mode")
        try require(zip(workspace.servers.first?.jumpServers ?? [], keyed.jumpServers ?? []).allSatisfy { SharedSSHJumps.sameDefinition($0, $1) }, "Editing discarded jump keys")
        let migrated = try SSHPasswordMemory.scopeIdentifier(for: draft.server) + ":fixture"
        try require(try credentials.read(migrated) == "fixture-only" && credentials.read(oldAccount) == nil,
                    "Saving edited configuration orphaned legacy credentials")
        var passwordServer = Server(name: "Password jump", host: "target.test")
        passwordServer.jumpServers = [SSHJumpServer(host: "bastion.test", user: "jump", authentication: .password)]
        let hopID = passwordServer.jumpServers![0].id
        try require(workspace.save(passwordServer, jumpPasswords: [hopID: "fixture-jump"]), "Jump password save failed")
        let jumpAccount = try SSHJumpCredentials.account(server: passwordServer, index: 0)
        try require(try credentials.read(jumpAccount) == "fixture-jump", "Configured secret missing")
        try require(workspace.save(passwordServer, jumpPasswords: [hopID: ""]), "Blank save failed")
        try require(try credentials.read(jumpAccount) == "fixture-jump", "Blank secret erased password")
        let copyDraft = ServerDraft(server: Server(host: "other.test"))
        copyDraft.useJumpPreset(SSHJumpPreset.available(in: [passwordServer])[0])
        try require(copyDraft.jumpServers.first?.id != hopID && copyDraft.jumpPasswords.isEmpty, "Preset copied a row ID or plaintext secret")
        try require(workspace.save(copyDraft.server), "Copied route save failed")
        let associations = CredentialSettingsState.matching(try credentials.list(), references: [
            CredentialSessionReference(server: passwordServer, label: "A"),
            CredentialSessionReference(server: copyDraft.server, label: "B")])
        try require(associations[jumpAccount] == ["A", "B"], "Shared password associations missing")
        var invalid = passwordServer; invalid.jumpServers?[0].user = ""
        try require(!workspace.save(invalid, jumpPasswords: [hopID: "invalid"]), "Password without username accepted")
        try require(workspace.servers.first(where: { $0.id == passwordServer.id })?.jumpServers?[0].user == "jump", "Failed save changed server")
        try require(!String(decoding: JSONEncoder().encode(workspace.servers), as: UTF8.self).contains("fixture-jump"), "Secret leaked into session JSON")
        var destination = Server(name: "Destination password", host: "target.test", user: "dev")
        destination.authentication = .password
        try require(workspace.save(destination, password: "fixture-destination"), "Destination password save failed")
        let destinationAccount = try SSHPasswordMemory.destinationAccount(for: destination)
        try require(try credentials.read(destinationAccount) == "fixture-destination", "Destination secret missing")
        destination.name = "Renamed destination"
        try require(workspace.save(destination), "Blank destination save failed")
        try require(try credentials.read(destinationAccount) == "fixture-destination", "Blank destination erased secret")
        try require(workspace.save(destination, password: "fixture-replacement"), "Destination replacement failed")
        destination.authentication = .key
        try require(workspace.save(destination, password: "ignored-key-mode"), "Key mode save failed")
        try require(try credentials.read(destinationAccount) == "fixture-replacement", "Key mode replaced password")
        destination.authentication = .password; destination.user = ""
        try require(!workspace.save(destination, password: "invalid"), "Destination password without username accepted")
        try require(workspace.servers.first(where: { $0.id == destination.id })?.user == "dev", "Invalid save mutated destination")
        let sharedBefore = workspace.servers.first(where: { $0.id == passwordServer.id })!
        let sharedID = sharedBefore.jumpServers![0].profileID!
        try require(workspace.jumpReferences(sharedID).count == 2, "Shared profile reference list missing")
        var sharedEdit = sharedBefore; sharedEdit.jumpServers![0].identityFile = "/tmp/shared-key"
        try require(workspace.save(sharedEdit), "Shared profile update failed")
        try require(workspace.servers.first(where: { $0.id == copyDraft.server.id })?.jumpServers?[0].identityFile == "/tmp/shared-key", "Shared update did not reach referencing session")
        let reloaded = Workspace(applicationSupportDirectory: directory)
        try require(reloaded.servers == workspace.servers, "Shared definitions did not survive reload")
        let savedJSON = try String(contentsOf: directory.appendingPathComponent("MyTerm/servers.json"), encoding: .utf8)
        try require(!savedJSON.contains("fixture-destination") && !savedJSON.contains("fixture-replacement"), "Destination password leaked into JSON")
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let authenticationDraft = ServerDraft(server: keyed)
        authenticationDraft.password = "draft-only-password"
        let authenticationHost = NSHostingView(rootView: ServerAuthenticationEditor(draft: authenticationDraft))
        authenticationHost.frame = NSRect(x: 0, y: 0, width: 590, height: 200)
        let revealState = PasswordEntryState()
        let revealWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        revealWindow.isReleasedWhenClosed = false
        defer { revealWindow.close() }
        let revealHost = NSHostingView(rootView: PasswordEntryField(text: Binding(get: { authenticationDraft.password }, set: { authenticationDraft.password = $0 }), state: revealState))
        revealWindow.contentView = revealHost
        for revealed in [false, true, false] {
            revealState.revealed = revealed
            RunLoop.main.run(until: Date().addingTimeInterval(0.1)); revealHost.layoutSubtreeIfNeeded()
            let fields = descendants(revealHost).compactMap { $0 as? NSTextField }.filter { $0.stringValue == "draft-only-password" }
            try require(!fields.isEmpty && fields.contains(where: { $0 is NSSecureTextField }) == !revealed, "Password reveal/hide did not preserve masking and draft text")
        }
        for locale in [InterfaceLanguage.chinese, .english] {
            language.selection = locale
            for mode in [AuthenticationMode.password, .key, .automatic, .password] {
                authenticationDraft.authentication = mode
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                authenticationHost.layoutSubtreeIfNeeded()
                let fields = descendants(authenticationHost).compactMap { $0 as? NSTextField }
                try require(fields.contains(where: { $0 is NSSecureTextField }) == (mode == .password), "Password input does not follow authentication choice")
                try require(fields.contains(where: { $0.stringValue == keyed.identityFile }) == (mode == .key), "Private key input does not follow authentication choice")
                try require(authenticationDraft.server.identityFile == keyed.identityFile && authenticationDraft.password == "draft-only-password", "Switching modes discarded draft credentials")
            }
        }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)); root.layoutSubtreeIfNeeded() }
        try require(window.styleMask.contains(.resizable) && window.collectionBehavior.contains(.fullScreenPrimary), "Window cannot resize/fullscreen")
        for locale in [InterfaceLanguage.chinese, .english] {
            language.selection = locale
            for size in [NSSize(width: 640, height: 480), NSSize(width: 900, height: 760)] {
                window.setContentSize(size); settle()
                guard let scroll = descendants(root).compactMap({ $0 as? NSScrollView }).first(where: { $0.identifier?.rawValue == "ssh.editor.scroll" }),
                      let document = scroll.documentView else { throw ConfigurationError.invalid("SSH editor scrolling missing") }
                try require(scroll.hasVerticalScroller && !scroll.autohidesScrollers && scroll.scrollerStyle == .legacy, "Scrollbar is hidden")
                try require(document.frame.width <= scroll.contentSize.width + 1, "Horizontal overflow")
                let maximum = document.frame.height - scroll.contentSize.height
                try require(maximum > 100, "Expanded controls are compressed instead of scrollable")
                scroll.contentView.scroll(to: NSPoint(x: 0, y: maximum)); scroll.reflectScrolledClipView(scroll.contentView); settle()
                try require(scroll.contentView.bounds.origin.y > 100, "Cannot reach forwarding controls")
                let ports = descendants(document).compactMap { $0 as? NSTextField }.filter { ["12345", "23456", "12346", "23457", "12347"].contains($0.stringValue) }
                try require(ports.count == 5, "Forwarding fields missing")
                for field in ports { try require(field.bounds.width >= 140 && field.bounds.height >= 18, "Port field clipped") }
            }
        }
        window.setContentSize(NSSize(width: 640, height: 480)); settle()
        let before = window.frame
        window.performZoom(nil); settle()
        try require(window.frame.width > before.width || window.frame.height > before.height, "Maximize did not enlarge window")
        window.performZoom(nil); settle()
        try require(abs(window.frame.width - before.width) < 2 && abs(window.frame.height - before.height) < 2, "Restore changed window size")
        // Exercise the deletion action against persisted configuration, including
        // an empty list: reopening must never resurrect removed forwarding rules.
        let forwardingDraft = ServerDraft(server: server)
        let originalRules = forwardingDraft.forwards
        forwardingDraft.removeForward(id: originalRules[1].id)
        try require(forwardingDraft.forwards == [originalRules[0], originalRules[2]], "Deleting the middle forward changed other rules")
        try require(workspace.save(forwardingDraft.server), "Cannot save removed forward")
        let repository = ServerRepository(fileURL: directory.appendingPathComponent("MyTerm/servers.json"))
        try require(try repository.load().first(where: { $0.id == server.id })?.forwards == forwardingDraft.forwards,
                    "Removed forward returned on reload")
        for rule in originalRules { forwardingDraft.removeForward(id: rule.id) }
        try require(workspace.save(forwardingDraft.server), "Cannot save empty forwarding list")
        try require(try repository.load().first(where: { $0.id == server.id })?.forwards?.isEmpty == true,
                    "Empty forwarding list did not persist")
        forwardingDraft.forwards.append(originalRules[1])
        try require(workspace.save(forwardingDraft.server), "Cannot add after deleting all forwards")
        try require(try repository.load().first(where: { $0.id == server.id })?.forwards == [originalRules[1]],
                    "Re-added forwarding rule did not persist")
        print("PASS: forwarding removal: middle/remaining rules, stale IDs, empty save/reload and adding after deletion")
        print("PASS: SSH editor: expanded jumps/proxy/three forwarding types, Chinese/English, small/large windows, persistent scrollbar, unclipped ports and maximize/restore")
    }
}
