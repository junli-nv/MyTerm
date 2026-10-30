import Foundation

/// Keep protocol errors separate from transport failures. Unknown errors are never deletion evidence.
public struct CodexThreadRequestError: LocalizedError {
    public let method: String
    public let code: Int?
    public let message: String
    public var errorDescription: String? { "Codex " + method + ": " + message }
    public init(method: String, code: Int?, message: String) {
        self.method = method; self.code = code; self.message = message
    }
    public func isMissingThread(_ id: String) -> Bool {
        guard method == "thread/read", code == -32600, UUID(uuidString: id) != nil else { return false }
        // Deliberately narrow: new CLI error formats remain unverified, never auto-removed.
        return message == "no rollout found for thread id \(id)"
    }
}

public enum CodexConversationCheck: Equatable {
    case available(name: String?)
    case missing
    case unverified(reason: String)

    public static func read(id: String, directory: String, client: CodexThreadClient) -> Self {
        do { return .available(name: try client.read(id, directory: directory)) }
        catch let error as CodexThreadRequestError where error.isMissingThread(id) { return .missing }
        catch { return .unverified(reason: error.localizedDescription) }
    }
}
