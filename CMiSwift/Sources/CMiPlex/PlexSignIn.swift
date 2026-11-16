import Foundation

/// The sign-in flow as a small state machine, so the UI can just render the state and poll.
public enum PlexSignInState: Sendable {
    /// Ask the user to enter this code at plex.tv/link.
    case showingCode(String)
    /// Signed in to plex.tv; the user picks a server. Empty means no servers were found.
    case choosingServer([PlexServer])
    case signedIn(serverName: String)
    /// Something went wrong. Calling `start()` or `poll()` again picks up where it left off,
    /// e.g. back to the server list after choosing an unreachable server.
    case failed(String)
}

public actor PlexSignIn {
    let plex: Plex
    let pinLifetime: TimeInterval
    let now: @Sendable () -> Date

    private var pin: PlexPin?
    /// Signed in to plex.tv, but no server chosen yet.
    private var accountToken: String?
    private var servers: [PlexServer] = []

    /// plex.tv expires pins after 15 minutes, so a new one is made a bit before that.
    public init(plex: Plex, pinLifetime: TimeInterval = 14 * 60, now: @escaping @Sendable () -> Date = Date.init) {
        self.plex = plex
        self.pinLifetime = pinLifetime
        self.now = now
    }

    /// Creates a pin, or reuses an unexpired one.
    public func start() async -> PlexSignInState {
        if let state = await settledState() { return state }
        return await showCode()
    }

    /// Call every ~2s while showing the code. Makes a new code when the old one expires, and when the
    /// user has entered the code, signs in automatically if there's only one server.
    public func poll() async -> PlexSignInState {
        if let state = await settledState() { return state }
        guard let pin, !isExpired(pin) else { return await showCode() }

        let token: String?
        do {
            token = try await plex.accountToken(for: pin)
        } catch PlexError.pinExpired {
            self.pin = nil
            return await showCode()
        } catch {
            return .showingCode(pin.code)  // probably a network hiccup, try again next poll
        }
        guard let token else { return .showingCode(pin.code) }

        self.pin = nil
        do {
            servers = try await plex.servers(accountToken: token)
        } catch {
            return .failed("Couldn't get the Plex servers: \(Plex.describe(error))")
        }
        accountToken = token
        if servers.count == 1, let state = await signIn(to: servers[0]), case .signedIn = state {
            return state
        }
        return .choosingServer(servers)
    }

    public func choose(_ server: PlexServer.ID) async -> PlexSignInState {
        if await plex.isSignedIn {
            return .signedIn(serverName: await plex.serverName ?? "Plex")
        }
        guard accountToken != nil else { return await showCode() }
        guard let server = servers.first(where: { $0.id == server }) else { return .choosingServer(servers) }
        return await signIn(to: server) ?? .choosingServer(servers)
    }

    /// Signed in, or choosing a server. nil while there's a code to show.
    private func settledState() async -> PlexSignInState? {
        if await plex.isSignedIn {
            return .signedIn(serverName: await plex.serverName ?? "Plex")
        }
        if accountToken != nil {
            return .choosingServer(servers)
        }
        return nil
    }

    private func signIn(to server: PlexServer) async -> PlexSignInState? {
        do {
            guard try await plex.signIn(to: server, accountToken: accountToken) else {
                return .failed("Couldn't connect to \(server.name)")
            }
        } catch {
            return .failed("Couldn't sign in to \(server.name): \(Plex.describe(error))")
        }
        accountToken = nil
        servers = []
        return .signedIn(serverName: server.name)
    }

    private func showCode() async -> PlexSignInState {
        if let pin, !isExpired(pin) { return .showingCode(pin.code) }
        do {
            var pin = try await plex.createPin()
            pin.created = now()
            self.pin = pin
            return .showingCode(pin.code)
        } catch {
            pin = nil
            return .failed("Couldn't reach plex.tv: \(Plex.describe(error))")
        }
    }

    private func isExpired(_ pin: PlexPin) -> Bool {
        now().timeIntervalSince(pin.created) > pinLifetime
    }
}
