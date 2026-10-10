import SwiftUI
import AppKit
import MyTermCore

struct SSHJumpEditor: View {
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    @Binding var hop: SSHJumpServer
    @Binding var password: String
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
            EditorTextField(title: "跳板机地址", text: $hop.host, prompt: "IP 或域名")
            EditorTextField(title: "端口", text: $hop.port, prompt: "22")
            EditorTextField(title: "用户名", text: $hop.user)
            Picker("认证方式", selection: $hop.authentication) {
                Text("自动").tag(AuthenticationMode.automatic)
                Text("密码").tag(AuthenticationMode.password)
                Text("密钥").tag(AuthenticationMode.key)
            }
            if hop.authentication != .key {
                Text("跳板机密码（可选）")
                SecureField("留空使用已保存密码，否则连接时询问", text: $password)
                Text("填写密码需指定用户名。保存后，同一路径的跳板机共用加密密码；留空不会清除已有密码。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if hop.authentication != .password {
                HStack {
                    EditorTextField(title: "私钥文件", text: $hop.identityFile, prompt: "可选，使用默认密钥")
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
            Text("未保存密码时连接后询问；已保存密码被拒绝时提示更新。密钥口令仍在连接时输入。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}
