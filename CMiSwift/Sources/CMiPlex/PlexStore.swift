import Foundation

/// Reads and writes plex.json in the support folder, shared with the old Python app:
/// `{"url": "http://192.168.1.10:32400", "token": "...", "server_name": "...", "client_id": "..."}`.
/// Unknown keys are kept when writing. `server_id` and `account_token` are only written by this app, to find the
/// server again when its address changes.
public struct PlexStore: Sendable {
    public let fileURL: URL

    public init(supportFolder: URL) {
        fileURL = supportFolder.appendingPathComponent("plex.json")
    }

    struct Server: Sendable, Equatable {
        var url: String
        var token: String
        var serverName: String?
    }

    /// The signed in server, nil if url or token is missing.
    var server: Server? {
        let c = load()
        guard let url = c["url"] as? String, !url.isEmpty,
              let token = c["token"] as? String, !token.isEmpty
        else { return nil }
        return Server(url: url, token: token, serverName: c["server_name"] as? String)
    }

    public var isSignedIn: Bool { server != nil }

    public var serverName: String? { server?.serverName }

    /// Plex identifies devices by this, so it's generated once per install and kept across sign out.
    public func clientID() throws -> String {
        var c = load()
        if let id = c["client_id"] as? String, !id.isEmpty { return id }
        let id = UUID().uuidString.lowercased()
        c["client_id"] = id
        try save(c)
        return id
    }

    func signIn(url: String, token: String, serverName: String, serverID: String? = nil, accountToken: String? = nil) throws {
        var c = load()
        c["url"] = url
        c["token"] = token
        c["server_name"] = serverName
        c["server_id"] = serverID
        c["account_token"] = accountToken
        try save(c)
    }

    /// The server's clientIdentifier and the plex.tv account token, saved when signing in. Nil for sign ins
    /// made before they were saved, and by the old app.
    var serverLookup: (serverID: String, accountToken: String)? {
        let c = load()
        guard let id = c["server_id"] as? String, let token = c["account_token"] as? String else { return nil }
        return (id, token)
    }

    func changeURL(to url: String) throws {
        var c = load()
        c["url"] = url
        try save(c)
    }

    public func signOut() throws {
        var c = load()
        let keys = ["url", "token", "server_name", "server_id", "account_token"]
        guard keys.contains(where: { c[$0] != nil }) else { return }
        for key in keys { c[key] = nil }
        try save(c)
    }

    private func load() -> [String: Any] {
        guard let data = try? Data(contentsOf: fileURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    private func save(_ c: [String: Any]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: c, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL, options: .atomic)
    }
}
