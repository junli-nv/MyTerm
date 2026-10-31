import SwiftUI
import MyTermCore

private final class ForwardPresentation: ObservableObject {
    @Published var shown = false
}

struct SSHForwardButton: View {
    @ObservedObject var model: SSHForwardModel
    @StateObject private var presentation = ForwardPresentation()
    var body: some View {
        if !model.entries.isEmpty {
            TabBarButton(symbol: "arrow.left.arrow.right", tooltip: "端口转发状态与开关",
                         identifier: "tabbar.forwarding", selected: presentation.shown) {
                presentation.shown.toggle()
            }.frame(width: 28, height: 28).contentShape(Rectangle())
                .popover(isPresented: $presentation.shown) { SSHForwardView(model: model) }
        } else {
            // Keep the tab strip stationary during authentication and SSH/local switching.
            Color.clear.frame(width: 28, height: 28).accessibilityHidden(true)
        }
    }
}

struct SSHForwardView: View {
    @ObservedObject var model: SSHForwardModel
    @ObservedObject var language = LanguagePreferences.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("端口转发").font(.headline)
                Spacer()
                Button("刷新", action: model.refresh).disabled(model.busy)
            }
            Text("开关仅作用于当前 SSH 连接；重连重新开启配置中的规则。已开启不代表目标服务可达。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.entries) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(L10n.text(entry.rule.kind == .local ? "本地转发" : entry.rule.kind == .remote ? "远程转发" : "动态 SOCKS 转发"))
                                    .font(.headline)
                                Spacer()
                                Text(L10n.text(entry.state.rawValue)).foregroundStyle(entry.state == .failed || entry.state == .unknown ? .orange : .secondary)
                                if entry.state == .enabled || entry.state == .unknown {
                                    Button("关闭转发") { model.setEnabled(false, id: entry.id) }.disabled(model.busy || !model.connected)
                                }
                                if entry.state != .enabled && entry.state != .stopping {
                                    Button("开启") { model.setEnabled(true, id: entry.id) }.disabled(model.busy || !model.connected)
                                }
                            }
                            Text((try? entry.rule.arguments().joined(separator: " ")) ?? "")
                                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if !entry.detail.isEmpty {
                                Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Divider()
                    }
                }
            }
        }.padding(16).frame(width: 480, height: 320).environment(\.locale, language.locale)
    }
}
