import AppKit

/// AppKit inserts and validates system commands after the app installs its menus.
/// Translate only recognized system commands; never replace their targets or actions.
final class SystemMenuLocalizer {
    private weak var editMenu: NSMenu?
    private weak var windowMenu: NSMenu?
    private var observers: [NSObjectProtocol] = []
    private var updating = false

    init() {
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notice in
                guard let self, let menu = notice.object as? NSMenu, self.contains(menu) else { return }
                self.refresh()
            })
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func attach(edit: NSMenu, window: NSMenu) {
        editMenu = edit
        windowMenu = window
        refresh()
    }

    private func contains(_ menu: NSMenu) -> Bool {
        if menu === editMenu || menu === windowMenu { return true }
        return menu.supermenu.map { contains($0) } ?? false
    }

    func refresh() {
        guard !updating else { return }
        updating = true
        defer { updating = false }
        [editMenu, windowMenu].compactMap { $0 }.forEach { translate($0) }
    }

    private func translate(_ menu: NSMenu) {
        for item in menu.items {
            let action = item.action.map(NSStringFromSelector) ?? ""
            let isArrangement = menu.items.contains { $0.action.map(NSStringFromSelector) == "_zoomLeft:" }
            let isSystem = Self.actions.contains(action)
                || item.identifier?.rawValue == "_NSMenuItemAutoFillIdentifier"
                || item.submenu?.items.contains(where: {
                    ["_zoomLeft:", "_tileLeft:"].contains($0.action.map(NSStringFromSelector) ?? "")
                }) == true
                || (action.isEmpty && isArrangement)
            if isSystem, let pair = Self.titles.first(where: { $0.0 == item.title || $0.1 == item.title }) {
                let title = LanguagePreferences.shared.identifier == "en" ? pair.0 : pair.1
                if item.title != title { item.title = title }
            }
            if let child = item.submenu { translate(child) }
        }
    }

    // Selector names identify existing AppKit commands only; none are invoked here.
    private static let actions: Set<String> = [
        "_handleInsertFromContactsCommand:", "_handleInsertFromPasswordsCommand:", "_handleInsertFromCreditCardsCommand:",
        "startDictation:", "stopDictation:", "orderFrontCharacterPalette:",
        "performMiniaturize:", "miniaturizeAll:", "performZoom:", "zoomAll:", "toggleFullScreen:",
        "_zoomFill:", "_zoomCenter:", "_zoomLeft:", "_zoomRight:", "_zoomTop:", "_zoomBottom:",
        "_zoomTopLeft:", "_zoomTopRight:", "_zoomBottomLeft:", "_zoomBottomRight:",
        "_zoomLeftAndRight:", "_zoomLeftThreeUp:", "_zoomRightAndLeft:", "_zoomRightThreeUp:",
        "_zoomTopAndBottom:", "_zoomTopThreeUp:", "_zoomBottomAndTop:", "_zoomBottomThreeUp:",
        "_zoomQuarters:", "_zoomUntile:", "_tileLeft:", "_tileRight:",
        "_removeWindowFromStageManagerSet:", "selectPreviousTab:", "selectNextTab:",
        "moveTabToNewWindow:", "mergeAllWindows:", "toggleTabBar:", "toggleTabOverview:"
    ]

    private static let titles: [(String, String)] = [
        ("AutoFill", "自动填充"),
        ("Contact…", "联系人…"),
        ("Passwords…", "密码…"),
        ("Credit Card…", "信用卡…"),
        ("Start Dictation", "开始听写"),
        ("Stop Dictation", "停止听写"),
        ("Emoji & Symbols", "表情与符号"),
        ("Minimize", "最小化"),
        ("Minimize All", "全部最小化"),
        ("Zoom", "缩放"),
        ("Zoom All", "全部缩放"),
        ("Fill", "填充"),
        ("Center", "居中"),
        ("Enter Full Screen", "进入全屏幕"),
        ("Exit Full Screen", "退出全屏幕"),
        ("Move & Resize", "移动与调整大小"),
        ("Halves", "二等分"),
        ("Left", "左侧"),
        ("Right", "右侧"),
        ("Top", "顶部"),
        ("Bottom", "底部"),
        ("Quarters", "四等分"),
        ("Top Left", "左上"),
        ("Top Right", "右上"),
        ("Bottom Left", "左下"),
        ("Bottom Right", "右下"),
        ("Arrange", "排列"),
        ("Left & Right", "左侧与右侧"),
        ("Left & Quarters", "左侧与四等分"),
        ("Right & Left", "右侧与左侧"),
        ("Right & Quarters", "右侧与四等分"),
        ("Top & Bottom", "顶部与底部"),
        ("Top & Quarters", "顶部与四等分"),
        ("Bottom & Top", "底部与顶部"),
        ("Bottom & Quarters", "底部与四等分"),
        ("Return to Previous Size", "恢复上一个大小"),
        ("Full Screen Tile", "全屏幕平铺"),
        ("Left of Screen", "屏幕左侧"),
        ("Right of Screen", "屏幕右侧"),
        ("Remove Window from Set", "从组中移除窗口"),
        ("Show Previous Tab", "显示上一个标签页"),
        ("Show Next Tab", "显示下一个标签页"),
        ("Move Tab to New Window", "将标签页移到新窗口"),
        ("Merge All Windows", "合并所有窗口"),
        ("Show Tab Bar", "显示标签页栏"),
        ("Hide Tab Bar", "隐藏标签页栏"),
        ("Show All Tabs", "显示所有标签页"),
        ("Exit Tab Overview", "退出标签页概览"),
    ]
}
