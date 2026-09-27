import AppKit

/// Exercise deferred native insertion and repeated language changes without relaunching.
enum SystemMenuLocalizationCheck {
    static func run() throws {
        let original = LanguagePreferences.shared.selection
        defer { LanguagePreferences.shared.selection = original }
        for language: InterfaceLanguage in [.english, .chinese, .english, .chinese] {
            LanguagePreferences.shared.selection = language
            guard let main = NSApp.mainMenu,
                  let edit = main.items.first(where: { $0.title == L10n.text("编辑") })?.submenu,
                  let windows = NSApp.windowsMenu else { throw failure("Missing app menus") }
            // Opening the real menu lets AppKit inject its window-arrangement subtree.
            let closeMenu = Timer(timeInterval: 0.1, repeats: false) { _ in windows.cancelTracking() }
            RunLoop.main.add(closeMenu, forMode: .eventTracking)
            windows.popUp(positioning: nil, at: NSPoint(x: 60, y: 60), in: NSApp.mainWindow?.contentView)
            closeMenu.invalidate()
            if let nativeCenter = windows.items.first(where: { $0.action == Selector(("_zoomCenter:")) }) {
                guard nativeCenter.title == (language == .english ? "Center" : "居中") else {
                    throw failure("Native window menu language")
                }
            }
            let center = windows.addItem(withTitle: "Center", action: Selector(("_zoomCenter:")), keyEquivalent: "")
            let autoFill = NSMenuItem(title: "AutoFill", action: nil, keyEquivalent: "")
            autoFill.identifier = NSUserInterfaceItemIdentifier("_NSMenuItemAutoFillIdentifier")
            edit.addItem(autoFill)
            let userWindow = windows.addItem(withTitle: "Center", action: Selector(("makeKeyAndOrderFront:")), keyEquivalent: "")
            let fullScreen = edit.addItem(withTitle: "Exit Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            defer {
                windows.removeItem(center); windows.removeItem(userWindow); edit.removeItem(fullScreen)
                edit.removeItem(autoFill)
            }
            let english = language == .english
            guard center.title == (english ? "Center" : "居中"),
                  autoFill.title == (english ? "AutoFill" : "自动填充"),
                  userWindow.title == "Center",
                  fullScreen.title == (english ? "Exit Full Screen" : "退出全屏幕"),
                  center.action == Selector(("_zoomCenter:")) else { throw failure("Deferred system item localization: \(language), center=\(center.title), autofill=\(autoFill.title), window=\(userWindow.title), fullscreen=\(fullScreen.title), key=\(fullScreen.keyEquivalent), action=\(String(describing: center.action))") }
            // AppKit can validate/change a title again when the menu opens.
            let shortcut = fullScreen.keyEquivalent
            let modifiers = fullScreen.keyEquivalentModifierMask
            fullScreen.title = english ? "退出全屏幕" : "Exit Full Screen"
            guard fullScreen.keyEquivalent == shortcut, fullScreen.keyEquivalentModifierMask == modifiers else {
                throw failure("Changed native shortcut")
            }
            center.title = english ? "居中" : "Center"
            guard center.title == (english ? "Center" : "居中") else { throw failure("Revalidated system title") }
        }
        print("PASS: live system menu localization and command preservation")
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "SystemMenuLocalizationCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
