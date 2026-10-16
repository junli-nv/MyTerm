import AppKit
import SwiftUI

/// Native dialog actions retain standard Escape/Return behavior and a fixed hit area.
struct CodexLaunchActions: NSViewRepresentable {
    let enabled: Bool
    let cancel: () -> Void
    let launch: () -> Void
    func makeNSView(context: Context) -> CodexLaunchActionRow { CodexLaunchActionRow() }
    func updateNSView(_ view: CodexLaunchActionRow, context: Context) {
        view.cancelButton.title = L10n.text("取消")
        view.launchButton.title = L10n.text("确认并启动")
        view.launchButton.isEnabled = enabled
        view.onCancel = cancel; view.onLaunch = launch
    }
}

final class CodexLaunchActionRow: NSView {
    let cancelButton = NSButton(), launchButton = NSButton()
    var onCancel: (() -> Void)?, onLaunch: (() -> Void)?
    init() {
        super.init(frame: .zero)
        for button in [cancelButton, launchButton] {
            button.bezelStyle = .rounded
            button.setButtonType(.momentaryPushIn)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.target = self
            button.keyEquivalentModifierMask = []
            addSubview(button)
            button.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }
        cancelButton.identifier = .init("codex.chooser.cancel")
        launchButton.identifier = .init("codex.chooser.start")
        cancelButton.keyEquivalent = "\u{1b}"
        launchButton.keyEquivalent = "\r"
        cancelButton.action = #selector(cancel)
        launchButton.action = #selector(launch)
        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            launchButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            launchButton.leadingAnchor.constraint(greaterThanOrEqualTo: cancelButton.trailingAnchor, constant: 20)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func cancel() { onCancel?() }
    @objc private func launch() { onLaunch?() }
}
