import SwiftUI
import AppKit
import MyTermCore

struct SSHJumpEditor: View {
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    @Binding var hop: SSHJumpServer
    let position: Int
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(L10n.text("跳板机")) \(position)").font(.headline)
                Spacer()
                Button(action: moveUp) { Image(systemName: "arrow.up") }.help("上移").disabled(position == 1)
                Button(action: moveDown) { Image(systemName: "arrow.down") }.help("下移")
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }.help("删除")
            }
            TextField("跳板机地址", text: $hop.host, prompt: Text("IP 或域名"))
            TextField("端口", text: $hop.port, prompt: Text("22"))
            TextField("用户名", text: $hop.user)
            Picker("认证方式", selection: $hop.authentication) {
                Text("自动").tag(AuthenticationMode.automatic)
                Text("密码").tag(AuthenticationMode.password)
                Text("密钥").tag(AuthenticationMode.key)
            }
            if hop.authentication != .password {
                HStack {
                    TextField("私钥文件", text: $hop.identityFile, prompt: Text("可选，使用默认密钥"))
                    Menu("密钥库") {
                        ForEach((try? SSHKeyLibrary().list()) ?? []) { key in
                            Button(key.name) { hop.identityFile = key.url.path }
                        }
                    }.fixedSize()
                    Button("选择…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url { hop.identityFile = url.path }
                    }
                }
            }
            Text("连接时会分别提示各级跳板机的密码或密钥口令。密码可在登录成功后保存到应用本地加密数据库。").font(.caption).foregroundStyle(.secondary)
        }.padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}
