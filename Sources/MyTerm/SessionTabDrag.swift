import SwiftUI

extension Workspace {
    /// Move to the target's current position: leftward before it, rightward after it.
    /// Keep the same session objects and selected UUID; never reconnect a terminal.
    @discardableResult
    func moveSessionTab(_ id: UUID, to targetID: UUID) -> Bool {
        guard let source = sessions.firstIndex(where: { $0.id == id }),
              let destination = sessions.firstIndex(where: { $0.id == targetID }) else { return false }
        guard source != destination else { return true }
        var reordered = sessions
        reordered.insert(reordered.remove(at: source), at: destination)
        sessions = reordered
        return true
    }
}

/// A private drag type keeps terminal tabs separate from files and saved-server drags.
struct SessionTabDrag {
    static let typeIdentifier = "local.myterm.session-tab"
    let id: UUID

    var itemProvider: NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: Self.typeIdentifier, visibility: .ownProcess) { completion in
            completion(Data(id.uuidString.utf8), nil)
            return nil
        }
        return provider
    }

    @discardableResult
    static func receive(_ providers: [NSItemProvider], workspace: Workspace, targetID: UUID,
                        completion: @escaping (Bool) -> Void = { _ in }) -> Bool {
        guard providers.count == 1, let provider = providers.first,
              provider.hasItemConformingToTypeIdentifier(typeIdentifier) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            let id = data.flatMap { String(data: $0, encoding: .utf8) }.flatMap(UUID.init(uuidString:))
            DispatchQueue.main.async {
                // Either tab may have closed while the asynchronous provider was loading.
                guard let id else { completion(false); return }
                completion(workspace.moveSessionTab(id, to: targetID))
            }
        }
        return true
    }
}

private final class TabDropFeedback: ObservableObject {
    @Published var targeted = false
}

private struct SessionTabDropDelegate: DropDelegate {
    let workspace: Workspace
    let targetID: UUID
    let feedback: TabDropFeedback

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [SessionTabDrag.typeIdentifier]) }
    func dropEntered(info: DropInfo) { feedback.targeted = validateDrop(info: info) }
    func dropExited(info: DropInfo) { feedback.targeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
    }
    func performDrop(info: DropInfo) -> Bool {
        feedback.targeted = false
        // Commit only on drop. Leaving the tab bar or cancelling must not reorder tabs.
        return SessionTabDrag.receive(info.itemProviders(for: [SessionTabDrag.typeIdentifier]),
                                      workspace: workspace, targetID: targetID)
    }
}

struct SessionTabDropTarget: ViewModifier {
    let workspace: Workspace
    let sessionID: UUID
    @StateObject private var feedback = TabDropFeedback()

    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(feedback.targeted ? Color.accentColor : .clear, lineWidth: 2)
                .allowsHitTesting(false))
            .onDrop(of: [SessionTabDrag.typeIdentifier],
                    delegate: SessionTabDropDelegate(workspace: workspace, targetID: sessionID, feedback: feedback))
    }
}
