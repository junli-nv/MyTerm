import SwiftUI

final class PasswordEntryState: ObservableObject {
    @Published var revealed = false
}

/// Visibility is transient editor state; the binding holds only the user's draft.
struct PasswordEntryField: View {
    @Binding var text: String
    @StateObject private var state = PasswordEntryState()
    init(text: Binding<String>, state: PasswordEntryState = PasswordEntryState()) {
        _text = text; _state = StateObject(wrappedValue: state)
    }
    var body: some View {
        HStack {
            Group {
                if state.revealed {
                    TextField("留空使用已保存密码，否则连接时询问", text: $text)
                } else {
                    SecureField("留空使用已保存密码，否则连接时询问", text: $text)
                }
            }
            Button(L10n.text(state.revealed ? "隐藏密码" : "显示密码")) { state.revealed.toggle() }
                .fixedSize()
        }.onDisappear { state.revealed = false }
    }
}
