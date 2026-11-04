import SwiftUI

/// A native read-only field keeps selection and Copy in the AppKit responder chain.
/// Avoid rebuilding its field editor while a user is selecting a revealed password.
struct CredentialPasswordField: NSViewRepresentable {
    let password: String
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isEditable = false
        field.isSelectable = true
        field.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.maximumNumberOfLines = 1
        field.cell?.isScrollable = true
        field.identifier = NSUserInterfaceItemIdentifier("credentials.revealed")
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != password { field.stringValue = password }
    }
    static func dismantleNSView(_ field: NSTextField, coordinator: ()) {
        field.abortEditing()
        field.stringValue = ""
    }
}
