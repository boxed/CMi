import Foundation

extension Plex {
    /// Starts a sign in. The user enters the returned code at plex.tv/link.
    public func createPin() async throws -> PlexPin {
        var request = try request(plexTVURL("/api/v2/pins"), method: "POST")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("strong=false".utf8)
        let pin = try await decode(PinDTO.self, request)
        return PlexPin(id: pin.id, code: pin.code, created: Date())
    }

    /// The account token once the user has entered the code at plex.tv/link, nil while pending.
    /// Throws PlexError.pinExpired when plex.tv no longer knows the pin.
    public func accountToken(for pin: PlexPin) async throws -> String? {
        let request = try request(plexTVURL("/api/v2/pins/\(pin.id)"))
        do {
            return try await decode(PinDTO.self, request).authToken
        } catch PlexError.httpStatus {
            throw PlexError.pinExpired
        }
    }

    /// The media servers the account has access to, owned or shared.
    public func servers(accountToken: String) async throws -> [PlexServer] {
        let url = plexTVURL("/api/v2/resources", query: [
            URLQueryItem(name: "includeHttps", value: "1"),
            URLQueryItem(name: "includeRelay", value: "1"),
        ])
        return try await decode([ResourceDTO].self, request(url, token: accountToken)).compactMap(\.server)
    }

    /// Probes the server's connections and saves the first reachable one. Returns false if none answered.
    /// With the account token, the server can be found again if its address changes.
    public func signIn(to server: PlexServer, accountToken: String? = nil) async throws -> Bool {
        guard let url = await reachableURL(of: server) else { return false }
        try store.signIn(url: url, token: server.accessToken, serverName: server.name, serverID: server.id, accountToken: accountToken)
        return true
    }

    /// Asks plex.tv for the server's addresses again and saves the first one that answers. Returns false when
    /// that wasn't possible, also when it was tried less than a minute ago, so being offline doesn't make
    /// every request wait for this.
    func reconnect() async -> Bool {
        guard let lookup = store.serverLookup,
              lastReconnect.map({ Date().timeIntervalSince($0) > 60 }) ?? true
        else { return false }
        lastReconnect = Date()
        guard let server = try? await servers(accountToken: lookup.accountToken).first(where: { $0.id == lookup.serverID }),
              let url = await reachableURL(of: server)
        else { return false }
        try? store.changeURL(to: url)
        return true
    }

    /// The first connection that answers: local first, then remote, then Plex's relay.
    func reachableURL(of server: PlexServer) async -> String? {
        for connection in server.connectionsInProbeOrder {
            guard let request = try? request(url(base: connection.uri, path: "/identity"), token: server.accessToken, timeout: Self.probeTimeout)
            else { continue }
            if (try? await data(for: request)) != nil {
                return connection.uri
            }
        }
        return nil
    }
}
