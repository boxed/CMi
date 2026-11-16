import Foundation
import Testing
@testable import CMiPlex

@Suite struct PlexDownloadsTests {
    let fake = FakePlex()
    var server: String { fake.url("nas") }
    var folder: URL { fake.supportFolder.appending(path: "Plex downloads", directoryHint: .isDirectory) }

    init() throws {
        try fake.signIn(serverURL: fake.url("nas"))
        fake.route("\(server)/library/metadata/200/allLeaves", .json(Self.episodes(watched: ["1"])))
        for id in ["1", "2", "3", "4"] {
            fake.route("\(server)/library/metadata/\(id)", .json(Self.metadata(id)))
            fake.route("\(server)/library/parts/\(id)/file.mkv", .json("video \(id)"))
        }
        fake.route("\(server)/library/streams/3", .json("1\n00:00:01,000 --> 00:00:02,000\nHello\n"))
        fake.route("\(server)/:/scrobble", .status(200))
    }

    func makeDownloads() -> PlexDownloads {
        PlexDownloads(plex: fake.makePlex(), folder: folder)
    }

    /// Episodes 1–4 of show 200, in season 1.
    static func episodes(watched: Set<String>) -> String {
        let metadata = ["1", "2", "3", "4"].map { id in
            #"{"ratingKey": "\#(id)", "type": "episode", "title": "Episode \#(id)", "grandparentTitle": "Show", "parentIndex": 1, "index": \#(id), "viewCount": \#(watched.contains(id) ? 1 : 0)}"#
        }
        return #"{"MediaContainer": {"Metadata": [\#(metadata.joined(separator: ","))]}}"#
    }

    /// Episode 3 has subtitles in a file of their own, chosen in Plex.
    static func metadata(_ id: String) -> String {
        let streams = id == "3" ? #"{"streamType": 3, "codec": "srt", "language": "English", "selected": true, "key": "/library/streams/3"}"# : ""
        return #"""
        {"MediaContainer": {"Metadata": [{"ratingKey": "\#(id)", "type": "episode", "grandparentRatingKey": "200",
          "Media": [{"Part": [{"key": "/library/parts/\#(id)/file.mkv", "size": 7, "Stream": [\#(streams)]}]}]}]}}
        """#
    }

    func downloadedIDs(_ downloads: PlexDownloads) async -> [String] {
        await downloads.downloads().map(\.episode.id)
    }

    @Test func nextUnwatchedEpisodes() {
        let episodes = ["1", "2", "3", "4", "5"].map {
            PlexEpisode(id: $0, title: "", season: 1, index: Int($0), aired: nil, watched: $0 == "3", offset: 0, showTitle: "")
        }
        #expect(PlexDownloads.episodes(episodes, after: "1", count: 2).map(\.id) == ["2", "4"])
        #expect(PlexDownloads.episodes(episodes, after: "4", count: 2).map(\.id) == ["5"])
        #expect(PlexDownloads.episodes(episodes, after: nil, count: 2).map(\.id) == ["1", "2"])
        #expect(PlexDownloads.episodes(episodes, after: "gone", count: 2).map(\.id) == ["1", "2"])
    }

    @Test func downloadsTheTwoAfterTheOnePlaying() async throws {
        let downloads = makeDownloads()
        await downloads.played("2", showID: "200")
        #expect(await downloadedIDs(downloads) == ["3", "4"])

        let download = try #require(await downloads.download(of: "3"))
        #expect(download.showID == "200")
        #expect(download.episode.title == "Episode 3")
        #expect(download.video == folder.appending(path: "3/video.mkv"))
        #expect(try String(contentsOf: download.video, encoding: .utf8) == "video 3")
        #expect(download.subtitles == [folder.appending(path: "3/3.srt")])
        #expect(download.selectedSubtitles == download.subtitles.first)
        #expect(await downloads.download(of: "4")?.subtitles == [])
    }

    @Test func keepsTheOnePlayingUntilWatched() async throws {
        let downloads = makeDownloads()
        await downloads.played("2", showID: "200")
        await downloads.played("3", showID: "200")
        #expect(await downloadedIDs(downloads) == ["3", "4"])

        fake.route("\(server)/library/metadata/200/allLeaves", .json(Self.episodes(watched: ["1", "2", "3"])))
        await downloads.sync()
        #expect(await downloadedIDs(downloads) == ["4"])
    }

    @Test func offlineKeepsDownloadsAndReportsWatchedLater() async throws {
        let downloads = makeDownloads()
        await downloads.played("2", showID: "200")
        fake.route("\(server)/:/scrobble", .unreachable)
        fake.route("\(server)/library/metadata/200/allLeaves", .unreachable)
        await downloads.played("3", showID: "200")
        await downloads.markWatched("3")
        await downloads.sync()
        #expect(await downloadedIDs(downloads) == ["4"])
        #expect(await downloads.download(of: "3") != nil)   // still there, until the server knows

        fake.route("\(server)/:/scrobble", .status(200))
        fake.route("\(server)/library/metadata/200/allLeaves", .json(Self.episodes(watched: ["1", "2", "3"])))
        await downloads.sync()
        #expect(fake.requests(to: "/:/scrobble").last?.query("key") == "3")
        #expect(await downloads.download(of: "3") == nil)
        #expect(await downloadedIDs(downloads) == ["4"])
    }

    @Test func failedDownloadIsRetried() async throws {
        fake.route("\(server)/library/parts/4/file.mkv", .unreachable)
        let downloads = makeDownloads()
        await downloads.played("2", showID: "200")
        #expect(await downloadedIDs(downloads) == ["3"])

        fake.route("\(server)/library/parts/4/file.mkv", .json("video 4"))
        await downloads.sync()
        #expect(await downloadedIDs(downloads) == ["3", "4"])
    }
}
