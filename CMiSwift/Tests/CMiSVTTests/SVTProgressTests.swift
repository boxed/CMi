import Foundation
import Testing
@testable import CMiSVT

@Suite struct SVTProgressTests {
    let folder: URL

    init() throws {
        // Inside the package, never the system temp folder
        folder = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../scratch/CMiSVTTests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func episodes(_ count: Int) -> [SVTTeaser] {
        (1...count).map { SVTTeaser(path: "/video/e\($0)/show/\($0)", title: "\($0)") }
    }

    @Test func remembersAcrossLaunches() async throws {
        let progress = SVTProgress(supportFolder: folder)
        await progress.setPosition(of: "e1", title: "Show – 1", milliseconds: 60_000)
        await progress.markWatched("e2", title: "Show – 2")
        let reloaded = SVTProgress(supportFolder: folder)
        #expect(await reloaded.entry(for: "e1")?.milliseconds == 60_000)
        #expect(await reloaded.entry(for: "e2")?.watched == true)
        #expect(await reloaded.entry(for: "e3") == nil)
        try FileManager.default.removeItem(at: folder)
    }

    @Test func inProgressMostRecentFirst() async throws {
        let progress = SVTProgress(supportFolder: folder)
        await progress.setPosition(of: "a", title: "A", milliseconds: 1000)
        await progress.setPosition(of: "b", title: "B", milliseconds: 1000)
        await progress.setPosition(of: "c", title: "C", milliseconds: 1000)
        await progress.markWatched("c", title: "C")
        await progress.setPosition(of: "a", title: "A", milliseconds: 2000)
        #expect(await progress.inProgress().map(\.videoID) == ["a", "b"])
        try FileManager.default.removeItem(at: folder)
    }

    @Test func nextEpisode() async throws {
        let progress = SVTProgress(supportFolder: folder)
        let eps = episodes(4)
        // Nothing watched: that's just the first episode
        #expect(await progress.nextEpisode(in: eps) == nil)
        await progress.markWatched("e1", title: "1")
        await progress.markWatched("e2", title: "2")
        #expect(await progress.nextEpisode(in: eps)?.videoID == "e3")
        // One in progress wins
        await progress.setPosition(of: "e4", title: "4", milliseconds: 5000)
        #expect(await progress.nextEpisode(in: eps)?.videoID == "e4")
        // Everything watched
        await progress.markWatched("e3", title: "3")
        await progress.markWatched("e4", title: "4")
        #expect(await progress.nextEpisode(in: eps) == nil)
        try FileManager.default.removeItem(at: folder)
    }

    @Test func programPathOfEpisodes() {
        #expect(SVTTeaser(path: "/video/jz7vN6E/agenda/missnojet-mot-s", title: "").programPath == "/agenda")
        #expect(SVTTeaser(path: "/video/emyqarV/gift", title: "").programPath == nil)
        #expect(SVTTeaser(path: "/klipp/abc/agenda/klippet", title: "").programPath == nil)
        #expect(SVTTeaser(path: "/agenda", title: "").programPath == nil)
    }

    @Test func recentProgramsMostRecentFirst() async throws {
        let progress = SVTProgress(supportFolder: folder)
        await progress.markWatched("a1", title: "A – 1", programPath: "/a")
        await progress.markWatched("b1", title: "B – 1", programPath: "/b")
        await progress.setPosition(of: "film", title: "Film", milliseconds: 1000)
        await progress.setPosition(of: "a2", title: "A – 2", programPath: "/a", milliseconds: 1000)
        #expect(await progress.recentPrograms().map(\.path) == ["/a", "/b"])
        // Remembered, and kept when a later report doesn't know the program
        await progress.markWatched("a2", title: "A – 2")
        #expect(await SVTProgress(supportFolder: folder).entry(for: "a2")?.programPath == "/a")
        try FileManager.default.removeItem(at: folder)
    }
}
