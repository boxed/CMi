import Foundation
import Testing
@testable import CMiPlex

@Suite struct PlexStoreTests {
    @Test func readsFileWrittenByPythonApp() throws {
        let fake = FakePlex()
        let python = """
        {
            "client_id": "6f1c2a8e-1111-4222-8333-944455556666",
            "url": "http://192.168.1.10:32400",
            "token": "abc123",
            "server_name": "Living room"
        }
        """
        try Data(python.utf8).write(to: fake.store.fileURL)
        #expect(fake.store.isSignedIn)
        #expect(fake.store.serverName == "Living room")
        #expect(fake.store.server == .init(url: "http://192.168.1.10:32400", token: "abc123", serverName: "Living room"))
        #expect(try fake.store.clientID() == "6f1c2a8e-1111-4222-8333-944455556666")
    }

    @Test func handWrittenFileWithoutServerName() throws {
        let fake = FakePlex()
        try Data(#"{"url": "http://nas:32400", "token": "t"}"#.utf8).write(to: fake.store.fileURL)
        #expect(fake.store.isSignedIn)
        #expect(fake.store.serverName == nil)
    }

    @Test func notSignedInWithoutFileOrToken() throws {
        let fake = FakePlex()
        #expect(!fake.store.isSignedIn)
        try Data(#"{"url": "http://nas:32400", "client_id": "x"}"#.utf8).write(to: fake.store.fileURL)
        #expect(!fake.store.isSignedIn)
    }

    @Test func clientIDIsGeneratedOnceAndKeptAcrossSignOut() throws {
        let fake = FakePlex()
        let id = try fake.store.clientID()
        #expect(UUID(uuidString: id) != nil)
        #expect(try fake.store.clientID() == id)

        try fake.store.signIn(url: "http://nas:32400", token: "t", serverName: "NAS")
        #expect(fake.store.isSignedIn)
        try fake.store.signOut()
        #expect(!fake.store.isSignedIn)
        #expect(fake.store.serverName == nil)
        #expect(try fake.store.clientID() == id)

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: fake.store.fileURL)) as! [String: Any]
        #expect(json.keys.sorted() == ["client_id"])
    }

    @Test func writesKeysThePythonAppReadsAndKeepsUnknownOnes() throws {
        let fake = FakePlex()
        try Data(#"{"client_id": "c", "something_else": 1}"#.utf8).write(to: fake.store.fileURL)
        try fake.store.signIn(url: "http://nas:32400", token: "t", serverName: "NAS")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: fake.store.fileURL)) as! [String: Any]
        #expect(json["url"] as? String == "http://nas:32400")
        #expect(json["token"] as? String == "t")
        #expect(json["server_name"] as? String == "NAS")
        #expect(json["client_id"] as? String == "c")
        #expect(json["something_else"] as? Int == 1)
    }
}
