import SwiftUI
import MyTermCore

/// Fill the pane on wide windows; retain horizontal access to controls in narrow splits.
struct TerminalStatusBar: View {
    @ObservedObject var session: TerminalSession
    var body: some View {
        ScrollView(.horizontal) { HStack(spacing: 7) {
                Circle().fill(session.isRunning ? Color.mint : .secondary).frame(width: 6, height: 6)
                Text(L10n.text(session.status))
                if session.canReconnect { Button("重新连接", action: session.reconnect).controlSize(.small) }
                Spacer()
                if session.sftp != nil {
                    Toggle("SFTP 文件", isOn: $session.showSFTP).toggleStyle(.checkbox)
                        .help("展开 / 收起 SFTP 文件面板")
                }
                Toggle("锁定尺寸", isOn: $session.sizeLocked).toggleStyle(.checkbox)
                    .help("屏幕共享时保持终端大小；窗口变小时可滚动查看，取消后恢复自动适配。")
                Picker("编码", selection: $session.encoding) {
                    ForEach(TerminalEncoding.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.fixedSize().help("会话输入与输出编码；切换后作用于新文本，文件传输不受影响。")
                Text(session.executable == "/usr/bin/ssh" ? "SSH" : "LOCAL")
                if session.statusBarVisible {
                    Button { session.statusBarVisible = false } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.plain).help("收起底部状态栏")
                }
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 3)
                .containerRelativeFrame(.horizontal) { width, _ in max(760, width) }
            }.fixedSize(horizontal: false, vertical: true)
                .background(Color(nsColor: .windowBackgroundColor))
    }
}
