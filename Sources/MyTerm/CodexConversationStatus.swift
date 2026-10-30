import SwiftUI
import MyTermCore

/// Status is an observation, not a guarantee that a later resume will succeed.
struct CodexConversationStatus: View {
    let check: CodexConversationCheck?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch check {
            case .none:
                Text("尚未检查；可刷新对话").foregroundStyle(.secondary)
            case .available:
                Text("可恢复（元数据检查通过）").foregroundStyle(.secondary)
            case .missing:
                Text("未找到对话；可重试或移除记录").foregroundStyle(.orange)
            case .unverified(let reason):
                Text("暂时无法验证；请检查 CLI、代理和权限后重试").foregroundStyle(.orange)
                Text(L10n.text(reason)).foregroundStyle(.secondary)
            }
        }.font(.caption).fixedSize(horizontal: false, vertical: true)
    }
}
