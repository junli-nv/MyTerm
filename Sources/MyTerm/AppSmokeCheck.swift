#if DEBUG
import AppKit

/// Exercises the real window and PTY without connecting to a remote server.
enum AppSmokeCheck {
    static func run(_ workspace: Workspace) {
        let english = LanguagePreferences.shared.identifier == "en"
        guard L10n.text("设置…") == (english ? "Settings…" : "设置…"),
              L10n.text("导出偏好设置备份…") == (english ? "Export Preferences Backup…" : "导出偏好设置备份…") else {
            fail("Interface language resources did not load", workspace)
        }
        print("PASS: \(english ? "English" : "Chinese") interface localization resources")
        let previousWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        NSApp.mainMenu?.items.first?.submenu?.performActionForItem(at: 0)
        let aboutWindows = NSApp.windows.filter { !previousWindows.contains(ObjectIdentifier($0)) && $0.isVisible }
        func containsAppIcon(_ view: NSView) -> Bool {
            if let imageView = view as? NSImageView, let icon = imageView.image,
               icon.isValid, icon === (NSApp.delegate as? AppDelegate)?.applicationIcon { return true }
            return view.subviews.contains(where: containsAppIcon)
        }
        guard aboutWindows.contains(where: { $0.contentView.map(containsAppIcon) == true }) else {
            fail("About panel did not display the bundled application icon", workspace)
        }
        aboutWindows.forEach { $0.orderOut(nil) }
        print("PASS: About menu opens a panel displaying the bundled application icon")
        do { try GroupNameDialogCheck.run() }
        catch { fail(error.localizedDescription, workspace) }
        guard let first = workspace.selected, let window = first.terminal.window else {
            fail("Terminal was not attached to a window", workspace)
        }
        let language = LanguagePreferences.shared, originalLanguage = LanguagePreferences.shared.selection
        let originalPID = first.terminal.process.shellPid
        for (selection, menuTitle, settingsTitle) in [(InterfaceLanguage.english, "File", "Settings…"), (.chinese, "文件", "设置…")] {
            language.selection = selection
            guard L10n.text("设置…") == settingsTitle,
                  NSApp.mainMenu?.items.contains(where: { $0.title == menuTitle }) == true,
                  first.terminal.process.shellPid == originalPID, first.isRunning,
                  workspace.selectedID == first.id else {
                fail("Live language change lost menu translation or terminal session", workspace)
            }
        }
        language.selection = originalLanguage
        print("PASS: live English/Chinese switching updates menus and preserves the running terminal PID and selected tab")
        do { try MouseInteractionCheck.run(window: window) }
        catch { fail(error.localizedDescription, workspace) }
        do { try AppearanceHistoryCheck.run() }
        catch { fail(error.localizedDescription, workspace) }
        ThemeLayoutCheck.run()
        guard !first.showSFTP else { fail("SFTP must start collapsed", workspace) }
        let originalRows = first.terminal.getTerminal().rows
        first.terminal.send(txt: "printf 'MYTERM_%s\\n' 'SMOKE_OK'\n")
        var stage = 0
        var secondID: UUID?
        var closedPID: pid_t = 0
        var lockedGrid = (0, 0)
        var lockDeadline = Date()
        let deadline = Date().addingTimeInterval(20)
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if Date() > deadline { fail("Timed out at stage \(stage), grid=\(first.terminal.getTerminal().cols)x\(first.terminal.getTerminal().rows), locked=\(lockedGrid), frame=\(first.terminal.frame), window=\(window.frame)", workspace) }
            switch stage {
            case 0:
                guard first.terminal.process.shellPid == originalPID, first.isRunning else {
                    fail("Language redraw restarted the terminal process", workspace)
                }
                let text = String(decoding: first.terminal.getTerminal().getBufferAsData(), as: UTF8.self)
                guard text.contains("MYTERM_SMOKE_OK") else { return }
                workspace.duplicate(first)
                secondID = workspace.selectedID
                guard secondID != first.id, workspace.selected?.directory == first.directory else {
                    fail("Duplicated local session did not preserve directory or create a new tab", workspace)
                }
                stage = 1
            case 1:
                guard let second = workspace.selected, second.id == secondID, second.isRunning,
                      second.terminal.window != nil else { return }
                closedPID = second.terminal.process.shellPid
                workspace.selectedID = first.id
                stage = 2
            case 2:
                guard first.terminal.window != nil else { return }
                let text = String(decoding: first.terminal.getTerminal().getBufferAsData(), as: UTF8.self)
                guard text.contains("MYTERM_SMOKE_OK"), first.isRunning else {
                    fail("Tab switch lost terminal state", workspace)
                }
                window.setContentSize(NSSize(width: 1060, height: 620))
                stage = 3
            case 3:
                guard first.terminal.getTerminal().rows != originalRows else { return }
                guard let second = workspace.sessions.first(where: { $0.id == secondID }) else {
                    fail("Missing second session", workspace)
                }
                second.terminal.send(txt: "exit 7\n")
                stage = 4
            case 4:
                guard !workspace.sessions.contains(where: { $0.id == secondID }) else { return }
                guard closedPID > 0, kill(closedPID, 0) == -1, errno == ESRCH else { return }
                guard workspace.selectedID == first.id, first.isRunning else {
                    fail("Local exit changed the other active tab", workspace)
                }
                print("PASS: local Bash normal exit closes its tab and reaps the child, preserving the other tab")
                first.sizeLocked = true
                workspace.sidebarVisible.toggle()
                lockedGrid = (first.terminal.getTerminal().cols, first.terminal.getTerminal().rows)
                lockDeadline = Date().addingTimeInterval(0.7)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    window.setContentSize(NSSize(width: 1200, height: 800))
                    first.terminal.viewDidChangeBackingProperties()
                }
                stage = 5
            case 5:
                guard Date() >= lockDeadline else { return }
                guard lockedGrid == (first.terminal.getTerminal().cols, first.terminal.getTerminal().rows) else {
                    fail("Locked terminal grid changed during window/backing update", workspace)
                }
                first.sizeLocked = false; stage = 6
                workspace.sidebarVisible.toggle()
            default:
                guard first.terminal.getTerminal().rows != lockedGrid.1 else { return }
                print("PASS: locked terminal dimensions survive window/backing changes; unlock restores resize")
                if let content = window.contentView, let scroll = first.terminal.enclosingScrollView {
                    content.layoutSubtreeIfNeeded()
                    let frame = scroll.convert(scroll.bounds, to: content)
                    let top = content.isFlipped ? frame.minY : content.bounds.height - frame.maxY
                    print("Window layout: terminal top inset \(top) pt, status bar expanded \(first.statusBarVisible)")
                }
                if let pathIndex = ProcessInfo.processInfo.arguments.firstIndex(of: "--snapshot"),
                   ProcessInfo.processInfo.arguments.indices.contains(pathIndex + 1),
                   let view = window.contentView,
                   let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    let srgb = bitmap.converting(to: .sRGB, renderingIntent: .default) ?? bitmap
                    if let data = srgb.representation(using: .png, properties: [:]) {
                        do { try data.write(to: URL(fileURLWithPath: ProcessInfo.processInfo.arguments[pathIndex + 1])) }
                        catch { fail("Snapshot failed: \(error)", workspace) }
                    }
                }
                timer.invalidate()
                workspace.stopAll()
                print("PASS: window, PTY input/output, persistent tabs, resize, child cleanup")
                if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--tmux-check"),
                   ProcessInfo.processInfo.arguments.indices.contains(index + 1) {
                    let check = TmuxWindowCheck()
                    check.run(fixture: ProcessInfo.processInfo.arguments[index + 1]) { result in
                        switch result {
                        case .success: NSApp.terminate(nil)
                        case .failure(let error): fail(error.localizedDescription, workspace)
                        }
                    }
                } else if ProcessInfo.processInfo.arguments.contains("--transfer-check") {
                    let check = ZmodemWindowCheck()
                    check.run { result in
                        switch result {
                        case .success: NSApp.terminate(nil)
                        case .failure(let error): fail(error.localizedDescription, workspace)
                        }
                    }
                } else { NSApp.terminate(nil) }
            }
        }
    }

    private static func fail(_ message: String, _ workspace: Workspace) -> Never {
        workspace.stopAll()
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
#endif
