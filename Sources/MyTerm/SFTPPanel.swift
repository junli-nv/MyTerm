import SwiftUI
import AppKit

struct SFTPInlinePanel: View {
    @ObservedObject var model: SFTPModel
    var body: some View {
        if !model.detached { SFTPPanel(model: model).frame(minWidth: 310, idealWidth: 360, maxWidth: 520) }
    }
}

struct SFTPPanel: View {
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    @ObservedObject var model: SFTPModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("SFTP 文件", systemImage: "folder.badge.gearshape").font(.headline)
                Spacer()
                Button { model.detached ? model.dock() : model.showWindow() } label: {
                    Image(systemName: model.detached ? "rectangle.inset.filled" : "arrow.up.right.square")
                }.help(L10n.text(model.detached ? "收回 SFTP 面板" : "弹出 SFTP 窗口"))
                if model.connected || model.busy { Button("断开", action: model.disconnect) }
                else { Button("连接", action: model.connect) }
            }
            HStack {
                Button { model.navigate(model.path == "/" ? "/" : model.path + "/..") } label: { Image(systemName: "arrow.up") }
                TextField("远端目录", text: $model.pathInput).onSubmit { model.navigate(model.pathInput) }
                Button { model.navigate(model.path) } label: { Image(systemName: "arrow.clockwise") }
            }.disabled(!model.connected || model.busy)
            HStack {
                Button("上传 / 续传…", action: model.upload)
                Button("下载 / 续传…", action: model.download).disabled(model.selectedEntries.isEmpty)
            }.disabled(!model.connected || model.busy)
            SFTPFileTable(model: model).frame(minHeight: 120)
            Text("Command / Shift 多选；拖入文件上传，拖到 Finder 下载。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.busy {
                Text(model.transferFile).font(.caption).lineLimit(1).truncationMode(.middle)
                HStack {
                    if model.total > 0 { ProgressView(value: Double(model.completed), total: Double(model.total)) }
                    else { ProgressView().controlSize(.small) }
                    Button("取消", action: model.cancel)
                }
            }
            Text(L10n.text(model.status)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(6).fixedSize(horizontal: false, vertical: true)
            if model.showRate {
                Text("\(L10n.text(model.transferDirection)) \(L10n.text(model.rateIsAverage ? "平均速度" : "速度")): \(ByteCountFormatter.string(fromByteCount: Int64(min(Double(Int64.max / 2), max(0, model.bytesPerSecond))), countStyle: .file))/s")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }.controlSize(.small).padding(12).frame(minWidth: 310)
    }
}
