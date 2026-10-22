import AppKit
import MyTermCore

/// One resolver per transfer batch, including all recursive children. UI decisions stay on main.
final class TransferConflict {
    enum Choice { case overwrite, skip, overwriteAll, skipAll, cancel }
    typealias Handler = (URL, String, Bool) -> Choice
    private var all: Choice?
    private var cancelled = false
    private(set) var skipped = 0
    private let handler: Handler
    private let isActive: () -> Bool

    init(handler: @escaping Handler = TransferConflict.prompt, isActive: @escaping () -> Bool) {
        self.handler = handler; self.isActive = isActive
    }
    /// Worker-only gate, also used before committing a newly received file.
    func checkActive() throws {
        let ready = DispatchSemaphore(value: 0)
        var allowed = false
        RunLoop.main.perform(inModes: [.common]) {
            allowed = self.isActive() && !self.cancelled
            ready.signal()
        }
        ready.wait()
        if !allowed { throw CancellationError() }
    }
    func resolve(_ source: URL, target: String, canReplace: Bool) throws -> Bool {
        let ready = DispatchSemaphore(value: 0)
        var result: Result<Bool, Error> = .failure(CancellationError())
        RunLoop.main.perform(inModes: [.common]) {
            defer { ready.signal() }
            guard self.isActive(), !self.cancelled else { return }
            let choice: Choice
            if self.all == .skipAll { choice = .skip }
            else if self.all == .overwriteAll && canReplace { choice = .overwrite }
            else { choice = self.handler(source, target, canReplace) }
            guard self.isActive(), !self.cancelled else { return }
            switch choice {
            case .overwriteAll: self.all = .overwriteAll; result = .success(canReplace)
            case .overwrite: result = .success(canReplace)
            case .skipAll: self.all = .skipAll; self.skipped += 1; result = .success(false)
            case .skip: self.skipped += 1; result = .success(false)
            case .cancel: self.cancelled = true
            }
        }
        ready.wait()
        return try result.get()
    }
    static func prompt(_ source: URL, _ target: String, _ canReplace: Bool) -> Choice {
        return prompt(source, target, canReplace, downloading: false)
    }
    static func downloadPrompt(_ source: URL, _ target: String, _ canReplace: Bool) -> Choice {
        prompt(source, target, canReplace, downloading: true)
    }
    private static func prompt(_ source: URL, _ target: String, _ canReplace: Bool, downloading: Bool) -> Choice {
        let alert = NSAlert()
        alert.messageText = L10n.text(downloading ? "本地已有同名项目" : "远端已有同名项目")
        alert.informativeText = source.path + "\n→ " + target + "\n\n" + L10n.text(canReplace
            ? "请选择覆盖或跳过。全部选项仅对本次传输生效，续传临时文件会保留。"
            : "文件类型不兼容，不能覆盖目录、符号链接或特殊文件。可以跳过并继续。")
        let options: [(String, Choice)] = canReplace
            ? [("跳过", .skip), ("覆盖", .overwrite), ("全部覆盖", .overwriteAll), ("全部跳过", .skipAll), ("取消传输", .cancel)]
            : [("跳过", .skip), ("全部跳过", .skipAll), ("取消传输", .cancel)]
        for option in options { alert.addButton(withTitle: L10n.text(option.0)) }
        let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return options.indices.contains(index) ? options[index].1 : .cancel
    }
}
