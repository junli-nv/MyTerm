import SwiftUI

struct SavedServerDrag: Codable {
    let id: UUID
    static let typeIdentifier = "local.myterm.saved-server"

    var itemProvider: NSItemProvider {
        let provider = NSItemProvider()
        let data = try! JSONEncoder().encode(self) // A UUID-only payload cannot fail to encode.
        provider.registerDataRepresentation(forTypeIdentifier: SavedServerDrag.typeIdentifier, visibility: .ownProcess) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    /// Uses the same item-provider path for UI drops and regression checks.
    static func receive(_ providers: [NSItemProvider], workspace: Workspace, groupID: UUID?, targetServerID: UUID? = nil, completion: @escaping (Bool) -> Void = { _ in }) -> Bool {
        guard providers.count == 1, let provider = providers.first,
              provider.hasItemConformingToTypeIdentifier(SavedServerDrag.typeIdentifier) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: SavedServerDrag.typeIdentifier) { data, _ in
            let payload = data.flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
            DispatchQueue.main.async {
                guard let payload else { completion(false); return }
                if let targetServerID {
                    completion(workspace.promptGroupFromServers(payload.id, target: targetServerID))
                } else {
                    completion(workspace.moveDraggedServers([payload.id], to: groupID))
                }
            }
        }
        return true
    }
}

private final class GroupDropFeedback: ObservableObject {
    @Published var targeted = false
}

private struct ServerGroupDropDelegate: DropDelegate {
    let workspace: Workspace
    let groupID: UUID?
    let targetServerID: UUID?
    let feedback: GroupDropFeedback

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [SavedServerDrag.typeIdentifier])
    }
    func dropEntered(info: DropInfo) { feedback.targeted = validateDrop(info: info) }
    func dropExited(info: DropInfo) { feedback.targeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
    }
    func performDrop(info: DropInfo) -> Bool {
        feedback.targeted = false
        return SavedServerDrag.receive(info.itemProviders(for: [SavedServerDrag.typeIdentifier]), workspace: workspace, groupID: groupID, targetServerID: targetServerID)
    }
}

struct ServerGroupDropTarget: ViewModifier {
    @ObservedObject var workspace: Workspace
    let groupID: UUID?
    var targetServerID: UUID? = nil
    @StateObject private var feedback = GroupDropFeedback()

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(feedback.targeted ? Color.accentColor.opacity(0.15) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .onDrop(of: [SavedServerDrag.typeIdentifier], delegate: ServerGroupDropDelegate(workspace: workspace, groupID: groupID, targetServerID: targetServerID, feedback: feedback))
    }
}
