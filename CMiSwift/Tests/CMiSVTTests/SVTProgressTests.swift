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
}
