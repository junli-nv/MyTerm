import SwiftUI
import MyTermCore

/// Used for saved launch defaults and an existing association's explicit renewal.
struct CodexExecutionSettings: View {
    @Binding var limits: CodexExecutionLimits
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            number("授权时长（分钟）", value: $limits.minutes, range: "1–1440")
            number("每次授权命令额度", value: $limits.commands, range: "1–10000")
            number("单条命令长度（UTF-8 字节）", value: $limits.commandBytes, range: "256–32768")
            number("单条执行超时（秒）", value: $limits.timeoutSeconds, range: "1–3600")
            number("单条输出容量（MiB）", value: $limits.outputMiB, range: "1–8")
            Picker(L10n.text("命令审批"), selection: $limits.alwaysAllow) {
                Text(L10n.text("每条命令确认")).tag(false)
                Text(L10n.text("本会话始终允许")).tag(true)
            }.pickerStyle(.segmented)
            Text(L10n.text("继续授权沿用本标签的配置与审批模式。修改默认配置仅影响新标签；当前标签可通过执行设置修改并继续授权。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if (try? limits.validate()) == nil {
                Text(L10n.text("请将执行限制填写在标示范围内。")).foregroundStyle(.red)
            }
        }
    }
    private func number(_ label: String, value: Binding<Int>, range: String) -> some View {
        HStack {
            Text(L10n.text(label)).fixedSize(horizontal: false, vertical: true)
            Spacer()
            TextField(range, value: value, format: .number.grouping(.never)).frame(width: 110)
            Text(range).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
        }
    }
}
