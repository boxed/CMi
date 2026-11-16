import Foundation
import Testing
@testable import CMiPlex

@Suite struct PlexSignInTests {
    let fake = FakePlex()

    func pinRoute(authToken: String?) {
        fake.route("\(fake.plexTV)/api/v2/pins/1234567", .json(Payloads.pin(code: "ABCD", authToken: authToken)))
    }

    func servers(_ servers: String...) {
        fake.route("\(fake.plexTV)/api/v2/resources", .json("[\(([Payloads.player] + servers).joined(separator: ","))]"))
    }

    func server(_ name: String, host: String) -> String {
        Payloads.server(name: name, id: "id-\(name)", accessToken: "token-\(name)", connections: [(fake.url(host), true, false)])
    }

    /// Started, and the user has entered the code.
    func signInWithCode(_ signIn: PlexSignIn) async {
        fake.route("\(fake.plexTV)/api/v2/pins", .json(Payloads.pinCreated))
        guard case .showingCode("ABCD") = await signIn.start() else { Issue.record("no code"); return }
        pinRoute(authToken: nil)
        guard case .showingCode("ABCD") = await signIn.poll() else { Issue.record("not pending"); return }
        pinRoute(authToken: "account-token")
    }

    @Test func oneServerSignsInAutomatically() async throws {
        let signIn = PlexSignIn(plex: fake.makePlex())
        await signInWithCode(signIn)
        servers(server("Living room", host: "living"))
        fake.route("\(fake.url("living"))/identity", .json("{}"))

        guard case .signedIn(serverName: "Living room") = await signIn.poll() else { Issue.record("not signed in"); return }
        #expect(fake.store.server == .init(url: fake.url("living"), token: "token-Living room", serverName: "Living room"))
        #expect(fake.requests(to: "/api/v2/resources").first?.value(forHTTPHeaderField: "X-Plex-Token") == "account-token")
        // Further polls and starts just report it
        guard case .signedIn = await signIn.start() else { Issue.record("not signed in"); return }
    }

    @Test func twoServersLetTheUserChoose() async throws {
        let signIn = PlexSignIn(plex: fake.makePlex())
        await signInWithCode(signIn)
        servers(server("Living room", host: "living"), server("Office", host: "office"))
        fake.route("\(fake.url("office"))/identity", .json("{}"))

        guard case .choosingServer(let list) = await signIn.poll() else { Issue.record("not choosing"); return }
        #expect(list.map(\.name) == ["Living room", "Office"])
        #expect(!fake.store.isSignedIn)
        guard case .choosingServer = await signIn.poll() else { Issue.record("not choosing"); return }

        guard case .signedIn(serverName: "Office") = await signIn.choose("id-Office") else { Issue.record("not signed in"); return }
        #expect(fake.store.server?.token == "token-Office")
        #expect(fake.store.serverLookup?.serverID == "id-Office")
        #expect(fake.store.serverLookup?.accountToken != nil)
    }

    @Test func choosingAnUnreachableServerStaysOnTheChoice() async throws {
        let signIn = PlexSignIn(plex: fake.makePlex())
        await signInWithCode(signIn)
        servers(server("Living room", host: "living"), server("Office", host: "office"))
        fake.route("\(fake.url("living"))/identity", .unreachable)

        guard case .choosingServer = await signIn.poll() else { Issue.record("not choosing"); return }
        guard case .failed(let message) = await signIn.choose("id-Living room") else { Issue.record("didn't fail"); return }
        #expect(message.contains("Living room"))
        #expect(!fake.store.isSignedIn)
        guard case .choosingServer(let list) = await signIn.poll() else { Issue.record("not back to choosing"); return }
        #expect(list.count == 2)
    }

    @Test func oneUnreachableServerShowsTheChoice() async throws {
        let signIn = PlexSignIn(plex: fake.makePlex())
        await signInWithCode(signIn)
        servers(server("Living room", host: "living"))
        fake.route("\(fake.url("living"))/identity", .unreachable)

        guard case .choosingServer(let list) = await signIn.poll() else { Issue.record("not choosing"); return }
        #expect(list.count == 1)
    }

    @Test func noServers() async throws {
        let signIn = PlexSignIn(plex: fake.makePlex())
        await signInWithCode(signIn)
        servers()
        guard case .choosingServer(let list) = await signIn.poll() else { Issue.record("not choosing"); return }
        #expect(list.isEmpty)
    }

    @Test func pinUnknownToPlexTVGetsANewCode() async throws {
        let signIn = PlexSignIn(plex: fake.makePlex())
        await signInWithCode(signIn)
        fake.route("\(fake.plexTV)/api/v2/pins/1234567", .status(404))
        fake.route("\(fake.plexTV)/api/v2/pins", .json(#"{"id": 2, "code": "WXYZ", "authToken": null}"#))

        guard case .showingCode("WXYZ") = await signIn.poll() else { Issue.record("no new code"); return }
    }

    @Test func oldPinIsReplacedBeforePlexTVExpiresIt() async throws {
        let clock = Clock()
        let signIn = PlexSignIn(plex: fake.makePlex(), now: { clock.now })
        fake.route("\(fake.plexTV)/api/v2/pins", .json(Payloads.pinCreated))
        guard case .showingCode("ABCD") = await signIn.start() else { Issue.record("no code"); return }

        // start() reuses an unexpired pin
        clock.advance(13 * 60)
        guard case .showingCode("ABCD") = await signIn.start() else { Issue.record("no code"); return }
        #expect(fake.requests(to: "/api/v2/pins").count == 1)

        clock.advance(2 * 60)
        fake.route("\(fake.plexTV)/api/v2/pins", .json(#"{"id": 2, "code": "WXYZ", "authToken": null}"#))
        guard case .showingCode("WXYZ") = await signIn.poll() else { Issue.record("no new code"); return }
        #expect(fake.requests(to: "/api/v2/pins/1234567").isEmpty)
    }

    /// The UI calls start() on every menu refresh, so it must report the current state.
    @Test func startReportsCurrentStateThroughTheWholeFlow() async throws {
        let plex = fake.makePlex()
        let signIn = PlexSignIn(plex: plex)
        await signInWithCode(signIn)
        servers(server("Living room", host: "living"), server("Office", host: "office"))
        fake.route("\(fake.url("office"))/identity", .json("{}"))

        guard case .choosingServer = await signIn.poll() else { Issue.record("not choosing"); return }
        guard case .choosingServer(let list) = await signIn.start() else { Issue.record("start lost the choice"); return }
        #expect(list.count == 2)
        guard case .signedIn(serverName: "Office") = await signIn.choose("id-Office") else { Issue.record("not signed in"); return }
        guard case .signedIn(serverName: "Office") = await signIn.start() else { Issue.record("start lost sign in"); return }
        #expect(fake.requests(to: "/api/v2/pins").count == 1)

        await plex.signOut()
        fake.route("\(fake.plexTV)/api/v2/pins", .json(#"{"id": 2, "code": "WXYZ", "authToken": null}"#))
        guard case .showingCode("WXYZ") = await signIn.start() else { Issue.record("no fresh code after sign out"); return }
        guard case .showingCode("WXYZ") = await signIn.start() else { Issue.record("code not reused"); return }
        #expect(fake.requests(to: "/api/v2/pins").count == 2)
    }

    @Test func plexTVDownFails() async throws {
        let signIn = PlexSignIn(plex: fake.makePlex())
        fake.route("\(fake.plexTV)/api/v2/pins", .unreachable)
        guard case .failed = await signIn.start() else { Issue.record("didn't fail"); return }
    }

    @Test func alreadySignedIn() async throws {
        try fake.signIn(serverURL: fake.url("nas"))
        guard case .signedIn(serverName: "Living room") = await PlexSignIn(plex: fake.makePlex()).start() else {
            Issue.record("not signed in"); return
        }
        #expect(fake.requests.isEmpty)
    }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now = Date()
    var now: Date { lock.withLock { _now } }
    func advance(_ seconds: TimeInterval) { lock.withLock { _now += seconds } }
}
