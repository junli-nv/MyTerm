import AppKit
import MyTermCore

extension Workspace {
    var sharedJumpProfiles: [SSHJumpServer] {
        jumpProfiles.sorted { SSHJumpCredentials.label($0) < SSHJumpCredentials.label($1) }
    }

    func sharedJumpTitle(_ profile: SSHJumpServer) -> String {
        let authentication: String
        switch profile.authentication {
        case .automatic: authentication = L10n.text("自动")
        case .password: authentication = L10n.text("密码")
        case .key: authentication = L10n.text("密钥")
        }
        return SSHJumpCredentials.label(profile) + " · " + authentication + " · " + jumpReferences(profile.profileID ?? profile.id).joined(separator: ", ")
    }
    func jumpReferences(_ profileID: UUID) -> [String] {
        servers.filter { ($0.jumpServers ?? []).contains { $0.profileID == profileID } }.map(\.displayName).sorted()
    }
    func confirmSharedJumpChanges(_ edited: Server) -> Bool {
        let current = servers.flatMap { $0.jumpServers ?? [] }
        let changed = (edited.jumpServers ?? []).compactMap { hop -> UUID? in
            guard let id = hop.profileID, let old = current.first(where: { $0.profileID == id }),
                  !SharedSSHJumps.sameDefinition(old, hop) else { return nil }
            return id
        }
        guard !changed.isEmpty else { return true }
        let names = Set(changed.flatMap(jumpReferences)).sorted()
        let alert = NSAlert()
        alert.messageText = L10n.text("更新公共跳板机？")
        alert.informativeText = L10n.text("以下会话将在下次连接时使用新配置，已连接的会话不会中断：") + "\n\n" + names.joined(separator: "\n")
        alert.addButton(withTitle: L10n.text("更新公共配置"))
        alert.addButton(withTitle: L10n.text("取消"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
