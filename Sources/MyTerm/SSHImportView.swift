import SwiftUI
import MyTermCore

final class SSHImportModel: ObservableObject {
    @Published var candidates: [SSHConfigCandidate] = []
    @Published var selected = Set<String>()
    @Published var search = ""
    @Published var message = "读取 ~/.ssh/config…"
    init() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let candidates = try SSHConfigImporter().discover()
                DispatchQueue.main.async { self?.candidates = candidates; self?.message = "找到 \(candidates.count) 个具体主机别名" }
            } catch { DispatchQueue.main.async { self?.message = error.localizedDescription } }
        }
    }
}

struct SSHImportView: View {
    @ObservedObject var interfaceLanguage = LanguagePreferences.shared
    @StateObject private var model = SSHImportModel()
    @ObservedObject var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("从 SSH 配置导入").font(.title2.bold())
            Text("选择要加入侧栏的主机。连接时仍使用原 SSH 配置，配置文件不会被修改。")
                .font(.callout).foregroundStyle(.secondary)
            TextField("搜索别名", text: $model.search)
            List {
                ForEach(model.candidates.filter { model.search.isEmpty || $0.alias.localizedCaseInsensitiveContains(model.search) }) { candidate in
                    Toggle(isOn: Binding(get: { model.selected.contains(candidate.alias) }, set: {
                        if $0 { model.selected.insert(candidate.alias) } else { model.selected.remove(candidate.alias) }
                    })) {
                        VStack(alignment: .leading) {
                            Text(candidate.alias)
                            Text(candidate.source).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.disabled(workspace.servers.contains(where: { $0.host == candidate.alias }))
                }
            }.frame(height: 290)
            Text(model.message).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("导入所选（\(model.selected.count)）") {
                    if workspace.importServers(model.candidates.filter { model.selected.contains($0.alias) }.map(\.server)) { dismiss() }
                    else { model.message = workspace.error ?? "导入失败"; workspace.error = nil }
                }.disabled(model.selected.isEmpty).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 560)
    }
}
