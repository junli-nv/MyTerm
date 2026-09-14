import AppKit
import MyTermCore

enum SettingsTabsCheck {
    static func run() throws {
        try CodexBridgeCheck.run()
        try HistorySettingsCheck.run()
        try CredentialSettingsCheck.run()
        try SSHKeySettingsCheck.run()
        let controller = MouseSettingsController.shared
        let language = LanguagePreferences.shared, original = LanguagePreferences.shared.selection
        let originalPage = controller.selection.page
        controller.present()
        defer {
            language.selection = original
            controller.selection.page = originalPage
            controller.window?.orderOut(nil)
        }
        let window = controller.window!, root = window.contentView!
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.15)); root.layoutSubtreeIfNeeded() }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid("Settings tabs: " + message) }
        }
        for locale in [InterfaceLanguage.english, .chinese, .english, .chinese] {
            let selected = controller.selection.page
            language.selection = locale
            settle()
            try require(controller.selection.page == selected, "Locale change lost the selected page")
            let tabs = descendants(root).compactMap { $0 as? SettingsNativeTab }
            try require(tabs.count == 6, "Six tabs must remain visible")
            for page in SettingsPage.allCases {
                guard let tab = tabs.first(where: { $0.identifier?.rawValue == "settings.tab." + page.rawValue }) else {
                    throw ConfigurationError.invalid("Settings tab missing")
                }
                let frame = tab.convert(tab.bounds, to: root)
                try require(root.bounds.contains(frame) && frame.width >= 100 && frame.height >= 36, "Tab \(page.rawValue) is clipped: \(frame), root \(root.bounds)")
                try require(tab.title == L10n.text(page.title), "Stale tab translation")
                let point = tab.convert(NSPoint(x: tab.bounds.midX, y: tab.bounds.midY), to: nil)
                let now = ProcessInfo.processInfo.systemUptime
                let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: now + 0.01, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
                NSApp.postEvent(up, atStart: true)
                window.sendEvent(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: now, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!)
                settle()
                try require(controller.selection.page == page, "Actual tab click did not select page")
                try require(tab.state == .on, "Selected tab is not indicated")
                if page == .terminal {
                    let scrolls = descendants(root).compactMap { $0 as? NSScrollView }
                    try require(!scrolls.isEmpty, "Terminal/history settings are not scrollable")
                    for scroll in scrolls {
                        if let document = scroll.documentView {
                            try require(document.frame.width <= scroll.contentView.bounds.width + 1, "History settings overflow horizontally")
                        }
                    }
                }
                if page == .theme {
                    try require(descendants(root).contains(where: { $0 is NSScrollView }), "Theme page is empty")
                    if let index = CommandLine.arguments.firstIndex(of: "--theme-snapshots"), CommandLine.arguments.indices.contains(index + 1),
                       let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
                        root.cacheDisplay(in: root.bounds, to: bitmap)
                        let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
                        try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("settings-\(locale.rawValue).png"))
                    }
                }
            }
        }
        print("PASS: complete settings window: repeated live locale changes, six visible translated tabs, actual mouse clicks and retained selection")
    }
}
