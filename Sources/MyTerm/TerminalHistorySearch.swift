import AppKit
import SwiftTerm

/// Search uses the terminal's display buffer and cell mapping, including soft wraps.
/// It runs only on explicit navigation: output does not trigger rescans or steal scrolling.
final class TerminalHistorySearch: NSVisualEffectView, NSSearchFieldDelegate {
    weak var terminal: MouseTerminalView?
    let field = NSSearchField()
    let previous = NSButton()
    let next = NSButton()
    let close = NSButton()
    let options = NSPopUpButton()
    let status = NSTextField(labelWithString: "")
    private(set) var caseSensitive = false
    private(set) var wholeWord = false
    private(set) var regex = false
    private var languageObserver: NSObjectProtocol?
    private var statusKey = "输入后按回车搜索"

    init(terminal: MouseTerminalView) {
        self.terminal = terminal
        super.init(frame: .zero)
        material = .popover; blendingMode = .withinWindow; state = .active
        wantsLayer = true; layer?.cornerRadius = 6
        field.delegate = self; field.identifier = .init("terminal.history.search")
        field.target = self; field.action = #selector(submit)
        field.sendsSearchStringImmediately = false; field.sendsWholeSearchString = true
        configure(previous, symbol: "chevron.up", action: #selector(back))
        configure(next, symbol: "chevron.down", action: #selector(submit))
        configure(close, symbol: "xmark", action: #selector(dismissSearch))
        options.pullsDown = true; options.target = self; options.action = #selector(optionChanged)
        status.font = .systemFont(ofSize: 11); status.lineBreakMode = .byTruncatingTail
        [field, previous, next, close, options, status].forEach { addSubview($0) }
        localize()
        languageObserver = NotificationCenter.default.addObserver(forName: LanguagePreferences.didChange, object: nil, queue: .main) { [weak self] _ in self?.localize() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) } }
    private func configure(_ button: NSButton, symbol: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.bezelStyle = .texturedRounded; button.target = self; button.action = action
    }
    private func localize() {
        field.placeholderString = L10n.text("搜索终端历史")
        field.setAccessibilityLabel(L10n.text("搜索终端历史"))
        previous.toolTip = L10n.text("上一个匹配（Shift+回车）")
        next.toolTip = L10n.text("下一个匹配（回车）")
        close.toolTip = L10n.text("关闭搜索（Esc）")
        previous.setAccessibilityLabel(previous.toolTip!); next.setAccessibilityLabel(next.toolTip!); close.setAccessibilityLabel(close.toolTip!)
        options.removeAllItems()
        options.addItems(withTitles: [L10n.text("选项"), L10n.text("区分大小写"), L10n.text("整词匹配"), L10n.text("正则表达式")])
        options.item(at: 1)?.state = caseSensitive ? .on : .off
        options.item(at: 2)?.state = wholeWord ? .on : .off
        options.item(at: 3)?.state = regex ? .on : .off
        status.stringValue = L10n.text(statusKey)
        toolTip = L10n.text("只搜索终端仍保留的输出；全屏程序只包含已呈现的缓冲内容。")
    }
    override func layout() {
        super.layout()
        let width = bounds.width
        field.frame = NSRect(x: 8, y: 64, width: max(30, width - 48), height: 24)
        close.frame = NSRect(x: width - 34, y: 62, width: 28, height: 28)
        previous.frame = NSRect(x: 8, y: 32, width: 30, height: 28)
        next.frame = NSRect(x: 42, y: 32, width: 30, height: 28)
        options.frame = NSRect(x: 82, y: 32, width: max(65, width - 90), height: 28)
        status.frame = NSRect(x: 8, y: 8, width: max(0, width - 16), height: 18)
    }
    func show() {
        isHidden = false
        if field.stringValue.isEmpty, let selected = terminal?.selection.getSelectedText(), !selected.isEmpty, selected.count <= 4096 {
            field.stringValue = selected
        }
        statusKey = "输入后按回车搜索"; localize()
        window?.makeFirstResponder(field)
        field.selectText(nil)
    }
    func navigate(next forward: Bool) {
        guard let terminal else { return }
        let text = field.stringValue
        guard !text.isEmpty else { terminal.clearSearch(); statusKey = "输入后按回车搜索"; localize(); return }
        guard text.count <= 4096 else { statusKey = "搜索文本最多 4096 个字符"; localize(); return }
        if regex, (try? NSRegularExpression(pattern: text)) == nil {
            terminal.clearSearch(); statusKey = "正则表达式无效"; localize(); return
        }
        let settings = SearchOptions(caseSensitive: caseSensitive, regex: regex, wholeWord: wholeWord)
        let found = forward ? terminal.findNext(text, options: settings) : terminal.findPrevious(text, options: settings)
        statusKey = found ? "已定位匹配，可继续查找" : "未找到匹配"
        localize()
    }
    @objc private func submit() { navigate(next: NSApp.currentEvent?.modifierFlags.contains(.shift) != true) }
    @objc private func back() { navigate(next: false) }
    @objc func dismissSearch() {
        isHidden = true; terminal?.clearSearch()
        if let terminal { window?.makeFirstResponder(terminal) }
    }
    @objc private func optionChanged() {
        if options.indexOfSelectedItem == 1 { caseSensitive.toggle() }
        if options.indexOfSelectedItem == 2 { wholeWord.toggle() }
        if options.indexOfSelectedItem == 3 { regex.toggle() }
        terminal?.clearSearch(); statusKey = "输入后按回车搜索"; localize()
    }
    func controlTextDidChange(_ obj: Notification) {
        terminal?.clearSearch(); statusKey = "输入后按回车搜索"; localize()
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) { dismissSearch(); return true }
        if selector == #selector(NSResponder.insertNewline(_:)) { submit(); return true }
        return false
    }
}
