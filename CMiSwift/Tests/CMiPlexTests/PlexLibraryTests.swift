import Foundation
import Testing
@testable import CMiPlex

@Suite struct PlexLibraryTests {
    let fake = FakePlex()
    var server: String { fake.url("nas") }

    init() throws {
        try fake.signIn(serverURL: fake.url("nas") + "/")
    }

    @Test func requiresSignIn() async throws {
        let fake = FakePlex()
        await #expect(throws: PlexError.notSignedIn) {
            try await fake.makePlex().sections()
        }
    }

    @Test func sectionsAreMoviesAndShowsOnly() async throws {
        fake.route("\(server)/library/sections", .json(Payloads.sections))
        let sections = try await fake.makePlex().sections()
        #expect(sections == [
            PlexSection(id: "1", title: "Movies", kind: .movie),
            PlexSection(id: "2", title: "TV Shows", kind: .show),
        ])
        let request = try #require(fake.requests.first)
        #expect(request.value(forHTTPHeaderField: "X-Plex-Token") == "server-token")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func movies() async throws {
        fake.route("\(server)/library/sections/1/all", .json(Payloads.movies))
        let items = try await fake.makePlex().items(in: "1")
        #expect(items == [
            PlexItem(id: "101", title: "Alien", year: 1979, kind: .movie, watched: true, unwatchedEpisodes: 0),
            PlexItem(id: "102", title: "Brazil", year: 1985, kind: .movie, watched: false, unwatchedEpisodes: 0),
            PlexItem(id: "103", title: "Untitled home video", year: nil, kind: .movie, watched: false, unwatchedEpisodes: 0),
        ])
    }

    @Test func showsWithUnwatchedCounts() async throws {
        fake.route("\(server)/library/sections/2/all", .json(Payloads.shows))
        let items = try await fake.makePlex().items(in: "2")
        #expect(items == [
            PlexItem(id: "200", title: "The Wire", year: 2002, kind: .show, watched: false, unwatchedEpisodes: 47),
            PlexItem(id: "300", title: "Firefly", year: 2002, kind: .show, watched: true, unwatchedEpisodes: 0),
        ])
    }

    @Test func onDeckEpisodesAndMovies() async throws {
        fake.route("\(server)/library/onDeck", .json(Payloads.onDeck))
        let items = try await fake.makePlex().onDeck()
        #expect(items.map(\.id) == ["212", "305", "102"])
        #expect(items.map(\.title) == ["The Wire", "Firefly", "Brazil"])
        #expect(items.map(\.offset) == [1_200_000, 0, 3_000_000])
        #expect(items[0].episode?.season == 2)
        #expect(items[0].episode?.index == 2)
        #expect(items[0].episode?.inProgress == true)
        #expect(items[1].episode?.index == 3)
        #expect(items[2].episode == nil)
    }

    @Test func search() async throws {
        fake.route("\(server)/hubs/search", .json(Payloads.search))
        let results = try await fake.makePlex().search("brazil wire")
        #expect(results == [
            .movie(PlexItem(id: "102", title: "Brazil", year: 1985, kind: .movie, watched: false, unwatchedEpisodes: 0)),
            .show(PlexItem(id: "200", title: "The Wire", year: 2002, kind: .show, watched: false, unwatchedEpisodes: 47)),
            .episode(PlexEpisode(id: "212", title: "Collateral Damage", season: 2, index: 2, aired: nil, watched: false, offset: 60000, showTitle: "The Wire")),
        ])
        let url = try #require(fake.requests.last?.url)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.contains(URLQueryItem(name: "query", value: "brazil wire")))
    }

    @Test func episodesSortedWithProgress() async throws {
        fake.route("\(server)/library/metadata/200/allLeaves", .json(Payloads.episodes))
        let episodes = try await fake.makePlex().episodes(ofShow: "200")
        #expect(episodes.map(\.id) == ["201", "202", "211", "212"])
        #expect(episodes.map(\.season) == [1, 1, 2, 2])
        #expect(episodes.map(\.index) == [1, 2, 1, 2])
        #expect(episodes.map(\.watched) == [true, true, false, false])
        #expect(episodes.map(\.inProgress) == [false, false, false, true])
        #expect(episodes[3].offset == 1_200_000)
        #expect(episodes[0].aired == "2002-06-02")
        #expect(episodes[2].aired == nil)
        #expect(episodes.allSatisfy { $0.showTitle == "The Wire" })
        #expect(PlexEpisode.next(in: episodes)?.id == "212")
    }

    @Test func nextEpisode() {
        func episode(_ id: String, watched: Bool = false, offset: Int = 0) -> PlexEpisode {
            PlexEpisode(id: id, title: id, season: 1, index: Int(id), aired: nil, watched: watched, offset: offset, showTitle: "S")
        }
        // First unwatched when nothing is in progress
        #expect(PlexEpisode.next(in: [episode("1", watched: true), episode("2"), episode("3")])?.id == "2")
        // In progress wins over an earlier unwatched one
        #expect(PlexEpisode.next(in: [episode("1", watched: true), episode("2"), episode("3", offset: 5)])?.id == "3")
        // Not when it's the very first episode
        #expect(PlexEpisode.next(in: [episode("1"), episode("2")]) == nil)
        #expect(PlexEpisode.next(in: [episode("1", watched: true)]) == nil)
        #expect(PlexEpisode.next(in: []) == nil)
    }

    @Test func playbackURLHasTokenAndOffset() async throws {
        fake.route("\(server)/library/metadata/102", .json(Payloads.movieMetadata))
        let playback = try await fake.makePlex().playback(of: "102")
        #expect(playback.streamURL.absoluteString == "\(server)/library/parts/9/1600000000/file.mkv?X-Plex-Token=server-token")
        #expect(playback.offset == 600_000)
        #expect(playback.size == 123)
    }

    @Test func playbackWithoutMedia() async throws {
        fake.route("\(server)/library/metadata/5", .json(#"{"MediaContainer": {"size": 1, "Metadata": [{"ratingKey": "5", "type": "movie", "title": "X"}]}}"#))
        await #expect(throws: PlexError.noMedia) {
            try await fake.makePlex().playback(of: "5")
        }
    }

    @Test func progressAndScrobbleURLs() async throws {
        fake.route("\(server)/:/progress", .status(200))
        fake.route("\(server)/:/scrobble", .status(200))
        let plex = fake.makePlex()
        await plex.reportProgress(of: "102", milliseconds: 754_321)
        await plex.scrobble("102")

        let progress = try #require(fake.requests(to: "/:/progress").first)
        #expect(progress.query("key") == "102")
        #expect(progress.query("identifier") == "com.plexapp.plugins.library")
        #expect(progress.query("time") == "754321")
        #expect(progress.query("state") == "playing")
        #expect(progress.value(forHTTPHeaderField: "X-Plex-Token") == "server-token")

        let scrobble = try #require(fake.requests(to: "/:/scrobble").first)
        #expect(scrobble.url!.absoluteString == "\(server)/:/scrobble?key=102&identifier=com.plexapp.plugins.library")
    }

    @Test func progressIgnoresFailures() async {
        fake.route("\(server)/:/progress", .unreachable)
        await fake.makePlex().reportProgress(of: "102", milliseconds: 1)
    }
}
