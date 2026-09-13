import Foundation
import MyTermCore

struct SSHKeyReference {
    let path: String
    let session: String
}

enum SSHKeyAssociations {
    static func references(server: Server, session: String) -> [SSHKeyReference] {
        var result = [SSHKeyReference(path: server.identityFile, session: session)]
        for (index, hop) in (server.jumpServers ?? []).enumerated() {
            result.append(SSHKeyReference(path: hop.identityFile,
                session: session + " · " + L10n.text("跳板机") + " \(index + 1) (\(hop.host))"))
        }
        return result.filter { !$0.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    static func matching(_ key: ManagedSSHKey, references: [SSHKeyReference]) -> [String] {
        func canonical(_ path: String) -> String {
            URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath().path
        }
        let target = canonical(key.url.path)
        return Set(references.filter { canonical($0.path) == target }.map(\.session)).sorted()
    }
}
