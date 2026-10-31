import Foundation
import MyTermCore

/// Main-thread state for one SSH generation. Serial requests prevent contradictory
/// toggles, and generation checks prevent late replies from reviving closed sessions.
final class SSHForwardModel: ObservableObject {
    enum State: String { case waiting = "等待 SSH", starting = "正在开启", enabled = "已开启", stopping = "正在关闭", disabled = "已关闭", failed = "开启失败", unknown = "状态待确认", disconnected = "SSH 已断开" }
    struct Entry: Identifiable {
        let rule: PortForward
        var state: State = .waiting
        var detail = ""
        var id: UUID { rule.id }
    }
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var connected = false
    @Published private(set) var busy = false
    private var context: SSHLaunchContext?
    private var generation = UUID()
    private var timer: Timer?
    private var initialized = false
    private let queue = DispatchQueue(label: "MyTerm.SSHForwardControl")
    typealias Request = (String, SSHForwardControl.Operation, PortForward?) -> SSHForwardControl.Result
    private let request: Request
    init(request: @escaping Request = { SSHForwardControl.run(controlPath: $0, operation: $1, rule: $2) }) {
        self.request = request
    }
    func start(rules: [PortForward], context: SSHLaunchContext) {
        stop()
        self.context = context
        // Duplicate specifications share a listener in OpenSSH. Expose exactly one switch.
        var seen = Set<[String]>()
        entries = rules.filter { seen.insert((try? $0.arguments()) ?? [$0.id.uuidString]).inserted }.map { Entry(rule: $0) }
        guard !entries.isEmpty else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }
    func stop() {
        generation = UUID(); timer?.invalidate(); timer = nil
        context = nil; connected = false; busy = false; initialized = false
        for i in entries.indices { entries[i].state = .disconnected; entries[i].detail = "" }
    }
    deinit { timer?.invalidate() }
    func refresh() {
        guard !busy, let context else { return }
        perform(context: context, operation: .check) { [weak self] result in
            guard let self else { return }
            self.connected = result.succeeded
            if result.succeeded {
                self.initialized = true
                self.startNextWaiting()
            } else if !result.succeeded && self.initialized {
                for i in self.entries.indices {
                    self.entries[i].state = result.uncertain ? .unknown : .disconnected
                    self.entries[i].detail = result.detail
                }
            }
        }
    }
    private func startNextWaiting() {
        guard connected, let entry = entries.first(where: { $0.state == .waiting }) else { return }
        setEnabled(true, id: entry.id, continueInitial: true)
    }
    func setEnabled(_ enabled: Bool, id: UUID, continueInitial: Bool = false) {
        guard connected, !busy, let context, let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let rule = entries[index].rule
        entries[index].state = enabled ? .starting : .stopping; entries[index].detail = ""
        perform(context: context, operation: enabled ? .forward : .cancel, rule: rule) { [weak self] result in
            guard let self, let index = self.entries.firstIndex(where: { $0.id == id }) else { return }
            self.entries[index].state = result.succeeded ? (enabled ? .enabled : .disabled) :
                (result.uncertain || !enabled ? .unknown : .failed)
            self.entries[index].detail = result.succeeded ? "" : (result.detail.isEmpty ?
                L10n.text(result.uncertain ? "请求超时，转发状态待确认。可重试开启或关闭。" : "SSH 未能完成转发请求，请检查连接和规则。") : result.detail)
            if continueInitial { self.startNextWaiting() }
        }
    }
    private func perform(context: SSHLaunchContext, operation: SSHForwardControl.Operation, rule: PortForward? = nil,
                         completion: @escaping (SSHForwardControl.Result) -> Void) {
        busy = true
        let current = generation, request = request
        queue.async { [weak self, context] in
            let result = request(context.controlPath, operation, rule)
            RunLoop.main.perform { [weak self] in
                guard let self, self.generation == current else { return }
                self.busy = false; completion(result)
            }
        }
    }
}
