import Foundation
import Testing
@testable import CMiPlex

@Suite struct PlexAuthTests {
    @Test func createPinSendsPlexHeadersAndForm() async throws {
        let fake = FakePlex()
        fake.route("\(fake.plexTV)/api/v2/pins", .json(Payloads.pinCreated))
        let plex = fake.makePlex()

        let pin = try await plex.createPin()
        #expect(pin.id == 1234567)
        #expect(pin.code == "ABCD")

        let request = try #require(fake.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.httpBody == Data("strong=false".utf8))
        #expect(request.value(forHTTPHeaderField: "X-Plex-Product") == "CMi")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Device-Name") == "CMi")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Client-Identifier") == (try fake.store.clientID()))
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func pinPendingThenToken() async throws {
        let fake = FakePlex()
        let plex = fake.makePlex()
        let pin = PlexPin(id: 1234567, code: "ABCD", created: Date())

        fake.route("\(fake.plexTV)/api/v2/pins/1234567", .json(Payloads.pin(code: "ABCD", authToken: nil)))
        #expect(try await plex.accountToken(for: pin) == nil)

        fake.route("\(fake.plexTV)/api/v2/pins/1234567", .json(Payloads.pin(code: "ABCD", authToken: "account-token")))
        #expect(try await plex.accountToken(for: pin) == "account-token")
    }

    @Test func expiredPin() async throws {
        let fake = FakePlex()
        let plex = fake.makePlex()
        fake.route("\(fake.plexTV)/api/v2/pins/1234567", .status(404))
        await #expect(throws: PlexError.pinExpired) {
            try await plex.accountToken(for: PlexPin(id: 1234567, code: "ABCD", created: Date()))
        }
    }

    @Test func serversDropsNonServerResources() async throws {
        let fake = FakePlex()
        fake.route("\(fake.plexTV)/api/v2/resources", .json("""
        [\(Payloads.player),
         \(Payloads.server(name: "Living room", id: "srv-1", accessToken: "server-token", connections: [(fake.url("local"), true, false)])),
         \(Payloads.server(name: "Friend", id: "srv-2", owned: false, accessToken: "shared-token", connections: []))]
        """))
        let plex = fake.makePlex()

        let servers = try await plex.servers(accountToken: "account-token")
        #expect(servers.map(\.id) == ["srv-1", "srv-2"])
        #expect(servers.map(\.name) == ["Living room", "Friend"])
        #expect(servers.map(\.owned) == [true, false])
        #expect(servers[0].accessToken == "server-token")
        #expect(servers[0].connections == [PlexConnection(uri: fake.url("local"), local: true, relay: false)])

        let request = try #require(fake.requests.first)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "account-token")
        #expect(request.query("includeHttps") == "1")
        #expect(request.query("includeRelay") == "1")
    }

    @Test func probeOrderIsLocalThenRemoteThenRelay() {
        let server = PlexServer(id: "s", name: "S", owned: true, accessToken: "t", connections: [
            PlexConnection(uri: "relay", local: false, relay: true),
            PlexConnection(uri: "remote", local: false, relay: false),
            PlexConnection(uri: "local", local: true, relay: false),
            PlexConnection(uri: "local2", local: true, relay: false),
        ])
        #expect(server.connectionsInProbeOrder.map(\.uri) == ["local", "local2", "remote", "relay"])
    }

    @Test func signInFallsBackPastUnreachableConnectionAndSavesServerToken() async throws {
        let fake = FakePlex()
        let server = PlexServer(id: "srv-1", name: "Living room", owned: true, accessToken: "server-token", connections: [
            PlexConnection(uri: fake.url("relay", port: 8443), local: false, relay: true),
            PlexConnection(uri: fake.url("remote"), local: false, relay: false),
            PlexConnection(uri: fake.url("local"), local: true, relay: false),
        ])
        fake.route("\(fake.url("local"))/identity", .unreachable)
        fake.route("\(fake.url("remote"))/identity", .json(#"{"MediaContainer": {"size": 0, "machineIdentifier": "srv-1", "version": "1.40"}}"#))
        fake.route("\(fake.url("relay", port: 8443))/identity", .json("{}"))
        let plex = fake.makePlex()

        #expect(try await plex.signIn(to: server))
        #expect(fake.requests.map { $0.url!.host! } == [fake.host("local"), fake.host("remote")])
        #expect(fake.requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Plex-Token") == "server-token" })
        #expect(fake.requests.allSatisfy { $0.timeoutInterval == 3 })
        #expect(fake.store.server == .init(url: fake.url("remote"), token: "server-token", serverName: "Living room"))
        #expect(await plex.isSignedIn)
        #expect(await plex.serverName == "Living room")
    }

    @Test func signInFailsWhenNothingAnswers() async throws {
        let fake = FakePlex()
        let server = PlexServer(id: "srv-1", name: "Living room", owned: true, accessToken: "server-token", connections: [
            PlexConnection(uri: fake.url("local"), local: true, relay: false),
            PlexConnection(uri: fake.url("remote"), local: false, relay: false),
        ])
        fake.route("\(fake.url("local"))/identity", .unreachable)
        fake.route("\(fake.url("remote"))/identity", .status(401))
        let plex = fake.makePlex()

        #expect(try await plex.signIn(to: server) == false)
        #expect(!fake.store.isSignedIn)
    }

    @Test func signOutKeepsClientID() async throws {
        let fake = FakePlex()
        let id = try fake.store.clientID()
        try fake.signIn(serverURL: fake.url("local"))
        let plex = fake.makePlex()
        #expect(await plex.isSignedIn)
        await plex.signOut()
        #expect(await !plex.isSignedIn)
        #expect(try fake.store.clientID() == id)
    }

    /// Run with CMI_PLEX_LIVE=1 to check against the real plex.tv. Creates a PIN nobody will enter.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CMI_PLEX_LIVE"] != nil))
    func livePlexTV() async throws {
        let fake = FakePlex()
        let plex = Plex(store: fake.store)
        let pin = try await plex.createPin()
        #expect(pin.code.count >= 4)
        #expect(try await plex.accountToken(for: pin) == nil)
        print("Live plex.tv pin \(pin.id) code \(pin.code)")
    }
}
