import SwiftUI
import AppKit
import MyTermCore

/// Explicit modes expose only their own credential input. Switching modes keeps
/// draft values so a temporary selection does not destroy existing configuration.
struct ServerAuthenticationEditor: View {
    @ObservedObject var draft: ServerDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("认证方式", selection: $draft.authentication) {
                Text("自动").tag(AuthenticationMode.automatic)
                Text("密码").tag(AuthenticationMode.password)
                Text("密钥").tag(AuthenticationMode.key)
            }
            switch draft.authentication {
            case .password:
                Text("SSH 密码（可选）")
                SecureField("留空使用已保存密码，否则连接时询问", text: $draft.password)
                Text("填写密码需指定用户名。保存时写入本地加密数据库；留空保留已有密码，旧密码被拒绝时提示更新。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            case .key:
                HStack {
                    EditorTextField(title: "私钥文件", text: $draft.server.identityFile, prompt: "可选，使用默认密钥")
                    Menu("密钥库") {
                        ForEach((try? SSHKeyLibrary().list()) ?? []) { key in
                            Button(key.name) { draft.server.identityFile = key.url.path }
                        }
                    }.fixedSize()
                    Button("选择…", action: chooseKey)
                }
            case .automatic:
                Text("自动使用 SSH 配置和已有凭据。如需填写密码或选择私钥，请切换对应认证方式。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func chooseKey() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        if panel.runModal() == .OK, let url = panel.url { draft.server.identityFile = url.path }
    }
}
