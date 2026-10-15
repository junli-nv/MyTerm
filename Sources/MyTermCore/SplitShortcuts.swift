import Foundation

public struct SplitKeyBinding: Codable, Equatable {
    public var key: String
    public var shift: Bool
    public var control: Bool
    public var option: Bool
    public init(key: String, shift: Bool = true, control: Bool = false, option: Bool = false) {
        self.key = key; self.shift = shift; self.control = control; self.option = option
    }
    public func validate() throws {
        guard key.count == 1, key.utf8.allSatisfy({ (97...122).contains($0) }), shift || control || option else {
            throw ConfigurationError.invalid("分屏快捷键需使用 Command 加至少一个修饰键，以及一个英文字母。")
        }
        // Reserve app shortcuts and standard macOS editing/window commands.
        if (shift && !control && !option && ["i", "s", "e", "z", "a", "c", "q", "g"].contains(key))
            || (control && !shift && !option && ["s", "f", "q"].contains(key))
            || (option && !control && !shift && ["h", "m", "w", "v", "c", "f", "d", "t", "i", "s", "n", "l"].contains(key)) {
            throw ConfigurationError.invalid("此快捷键与已有菜单或 macOS 常用操作冲突，请选择其他组合。")
        }
    }
}
public struct SplitShortcuts: Codable, Equatable {
    public var horizontal = SplitKeyBinding(key: "h")
    public var vertical = SplitKeyBinding(key: "v")
    public init() {}
    public func validate() throws {
        try horizontal.validate(); try vertical.validate()
        guard horizontal != vertical else { throw ConfigurationError.invalid("上下分屏与左右分屏不能使用相同快捷键。") }
    }
}
