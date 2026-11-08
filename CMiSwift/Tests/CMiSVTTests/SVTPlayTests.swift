import Foundation
import Testing
@testable import CMiSVT

/// Serves canned responses by URL path. Each test registers its own host, so tests can run in parallel.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String: (status: Int, body: String)] = [:]
    static let lock = NSLock()

    static func register(_ url: String, status: Int = 200, _ body: String) {
        lock.withLock { responses[url] = (status, body) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!.absoluteString
        let response = Self.lock.withLock { Self.responses[url] } ?? (status: 404, body: "")
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// An svtplay.se page embedding the given GraphQL results, the way the real site does.
func page(_ queries: [String]) -> String {
    let entries = queries.enumerated().map { i, data in
        "\"\(i)\": {\"data\": \(String(data: try! JSONEncoder().encode(data), encoding: .utf8)!)}"
    }
    return """
    <html><head></head><body><div id="__next"></div>
    <script>window.URQL_DATA = {\(entries.joined(separator: ","))};</script></body></html>
    """
}

func teaser(_ heading: String, _ path: String, _ type: String = "Episode", sub: String? = nil) -> String {
    let subHeading = sub.map { "\"subHeading\": \"\($0)\"," } ?? ""
    return """
    {"heading": "\(heading)", \(subHeading) "item": {"restrictions": {"onlyAvailableInSweden": false}, "urls": {"svtplay": "\(path)"}, "__typename": "\(type)"}, "__typename": "Teaser"}
    """
}

let menuQuery = #"{"mainCategories": [], "mainMenuEvent": null, "legalNotices": [], "themes": []}"#

@Suite struct SVTPlayTests {
    let host = "svt-\(UUID().uuidString.prefix(8)).test"
    var svt: SVTPlay {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return SVTPlay(site: URL(string: "https://\(host)")!, videoAPI: URL(string: "https://api.\(host)/video")!,
                       session: URLSession(configuration: config))
    }

    @Test func teaserKinds() {
        #expect(SVTTeaser(path: "/video/jMdmAp9/nazistdonatorn/1-att-veta-sanningen", title: "").kind == .video(id: "jMdmAp9"))
        #expect(SVTTeaser(path: "/klipp/KZx79r2/varfor-firar-vi-halloween", title: "").kind == .video(id: "KZx79r2"))
        #expect(SVTTeaser(path: "/rapport", title: "").kind == .program(path: "/rapport"))
    }

    @Test func startPageSections() async throws {
        StubProtocol.register("https://\(host)/", page([menuQuery, """
        {"startForSvtPlay": {"analytics": {}, "modules": {"numberOfItemsAfter": 35, "items": [
            {"id": "hero_x", "hero": {"heading": "Gift vid första ögonkastet", "urls": {"svtplay": "/video/emyqarV/gift"}}, "defaultSelection": null, "showcaseSelection": null},
            {"id": "recommended_start", "hero": null, "showcaseSelection": {"name": "Vi rekommenderar", "items": [
                \(teaser("Agenda", "/video/jz7vN6E/agenda/missnojet-mot-s")),
                \(teaser("Nazistdonatorn", "/nazistdonatorn-mysteriet-pa-karolinska", "TvSeries"))]}},
            {"id": "breaking-1", "breaking": {"heading": "Extra"}, "showcaseSelection": null},
            {"id": "toplist_start", "toplistSelection": {"name": "Populärt", "items": [
                \(teaser("Nelly Rapp – monsteragent", "/video/KrJYnDv/nelly-rapp-monsteragent", "Single")),
                {"heading": "", "item": {"urls": {"svtplay": "/broken"}}},
                {"heading": "No item"}]}},
            {"id": "empty", "portraitSelection": {"name": "Tom lista", "items": []}}
        ]}}}
        """]))
        let sections = try await svt.startPage()
        #expect(sections.map(\.name) == ["Vi rekommenderar", "Populärt"])
        #expect(sections[0].items.map(\.kind) == [.video(id: "jz7vN6E"), .program(path: "/nazistdonatorn-mysteriet-pa-karolinska")])
        #expect(sections[1].items.map(\.title) == ["Nelly Rapp – monsteragent"])
    }

    @Test func programSeasonsOnly() async throws {
        StubProtocol.register("https://\(host)/the-series", page([menuQuery, """
        {"detailsPageByPath": {"heading": null, "item": {"name": "The Series", "__typename": "TvSeries"}, "smartStart": {"videoSvtId": "a"}, "modules": [
            {"id": "details-x", "details": {}, "defaultSelection": null},
            {"id": "season-1-x", "defaultSelection": {"name": "Säsong 1", "selectionType": "season", "itemsAdult": [
                \(teaser("1. Pilot", "/video/e1/the-series/1-pilot", sub: "28 min")), \(teaser("2. Second", "/video/e2/the-series/2-second"))]}},
            {"id": "season-2-x", "defaultSelection": {"name": "Säsong 2", "selectionType": "season", "itemsAdult": [
                \(teaser("1. Back", "/video/e3/the-series/1-back"))]}},
            {"id": "clips-x", "defaultSelection": {"name": "Klipp", "selectionType": "clips", "itemsAdult": [\(teaser("Trailer", "/klipp/c1/trailer", "Clip"))]}},
            {"id": "related", "defaultSelection": {"name": "Liknande", "itemsAdult": [\(teaser("Other", "/other", "TvSeries"))]}}
        ]}}
        """]))
        let program = try await svt.program("/the-series")
        #expect(program.title == "The Series")
        #expect(program.seasons.map(\.name) == ["Säsong 1", "Säsong 2"])
        #expect(program.seasons[0].items.map(\.videoID) == ["e1", "e2"])
        #expect(program.seasons[0].items[0].subtitle == "28 min")
    }

    @Test func seasonsInViewingOrder() {
        let s = { (name: String) in SVTSection(name: name, items: []) }
        #expect(SVTPlay.inViewingOrder([s("Säsong 10"), s("Säsong 2"), s("Säsong 1")]).map(\.name) == ["Säsong 1", "Säsong 2", "Säsong 10"])
        // Not all numbered: leave the site's order alone
        #expect(SVTPlay.inViewingOrder([s("Säsong 2"), s("Specials")]).map(\.name) == ["Säsong 2", "Specials"])
    }

    @Test func programWithoutSeasonsUsesItsEpisodeLists() async throws {
        StubProtocol.register("https://\(host)/rapport", page([menuQuery, """
        {"detailsPageByPath": {"item": {"name": "Rapport"}, "modules": [
            {"id": "details-x", "defaultSelection": null},
            {"id": "upcoming", "defaultSelection": {"name": "Kommande", "itemsAdult": [\(teaser("Later", "/video/u1/rapport/later"))]}},
            {"id": "latest-x", "defaultSelection": {"name": "Senaste", "selectionType": "latest", "itemsAdult": [\(teaser("Rapport 19.30", "/video/r1/rapport/19-30"))]}},
            {"id": "clips-x", "defaultSelection": {"name": "Klipp", "itemsAdult": [\(teaser("Klipp", "/klipp/c1/k", "Clip"))]}},
            {"id": "related", "defaultSelection": {"name": "Liknande", "itemsAdult": [\(teaser("Agenda", "/agenda", "TvShow"))]}}
        ]}}
        """]))
        let program = try await svt.program("/rapport")
        #expect(program.seasons.map(\.name) == ["Senaste"])
    }

    @Test func allPrograms() async throws {
        StubProtocol.register("https://\(host)/program", page([menuQuery, """
        {"mainCategories": [], "programAtillO": {"selections": [
            {"name": "A", "items": [{"heading": "A för Agnetha", "item": {"id": "1", "urls": {"svtplay": "/video/eyPwXA8/a-for-agnetha"}, "__typename": "Single"}},
                                    {"heading": "Agenda", "item": {"id": "2", "urls": {"svtplay": "/agenda"}, "__typename": "TvShow"}}]},
            {"name": "B", "items": []},
            {"name": "Ö", "items": [{"heading": "Öppet arkiv", "item": {"urls": {"svtplay": "/oppet-arkiv"}}}]}
        ]}}
        """]))
        let letters = try await svt.allPrograms()
        #expect(letters.map(\.name) == ["A", "Ö"])
        #expect(letters[0].items.map(\.kind) == [.video(id: "eyPwXA8"), .program(path: "/agenda")])
    }

    @Test func search() async throws {
        StubProtocol.register("https://\(host)/sok?q=agenda%20sverige", page([menuQuery, """
        {"searchPage": {"query": "agenda sverige", "flat": {"name": null, "hits": [
            {"categoryTeaser": null, "teaser": {"heading": "<em>Agenda</em>", "subHeading": "", "byline": "",
                "item": {"urls": {"svtplay": "/agenda"}, "__typename": "TvShow"}}},
            {"categoryTeaser": null, "teaser": {"heading": "<em>Agenda</em>", "subHeading": "<em>Agenda</em> special: Nordens svar", "byline": "Avsnitt",
                "item": {"urls": {"svtplay": "/video/KBMY9Xo/agenda/special"}, "__typename": "Episode"}}},
            {"categoryTeaser": {"heading": "Samhälle"}, "teaser": null},
            {"categoryTeaser": null, "teaser": {"heading": "Film om <em>Sverige</em>", "subHeading": "",
                "item": {"urls": {"svtplay": "/video/x1/film"}, "__typename": "Single"}}}
        ]}}}
        """]))
        let hits = try await svt.search("agenda sverige")
        #expect(hits.map(\.title) == ["Agenda", "Agenda – Agenda special: Nordens svar", "Film om Sverige"])
        #expect(hits.map(\.kind) == [.program(path: "/agenda"), .video(id: "KBMY9Xo"), .video(id: "x1")])
    }

    @Test func pageWithoutDataIsAnError() async throws {
        StubProtocol.register("https://\(host)/program", "<html><body>Maintenance</body></html>")
        await #expect(throws: SVTError.unexpectedPage) { try await svt.allPrograms() }
        StubProtocol.register("https://\(host)/gone", status: 404, "")
        await #expect(throws: SVTError.httpStatus(404)) { try await svt.program("/gone") }
    }

    @Test func streamPicksHLS() async throws {
        StubProtocol.register("https://api.\(host)/video/jMdmAp9", """
        {"svtId": "jJyp6WP", "programTitle": "Nazistdonatorn", "episodeTitle": "1. Att veta sanningen", "rights": {"drmCopyProtection": false},
         "videoReferences": [
            {"format": "dash", "url": "https://cdn.test/manifest.mpd"},
            {"format": "hls-full", "url": "https://cdn.test/hls.m3u8"},
            {"format": "hls", "url": "https://cdn.test/master-fmp4.m3u8?format=hls"}],
         "subtitleReferences": [
            {"url": "https://cdn.test/text/text-closed.vtt", "format": "webvtt", "type": "caption-sdh", "label": "Svenska (allt tal)"},
            {"url": "https://cdn.test/text/text-open.vtt", "format": "webvtt", "type": "subtitle", "label": "Svenska"}]}
        """)
        let stream = try await svt.stream(for: "jMdmAp9")
        #expect(stream.url.absoluteString == "https://cdn.test/master-fmp4.m3u8?format=hls")
        #expect(stream.title == "Nazistdonatorn – 1. Att veta sanningen")
        #expect(stream.defaultSubtitles == "Svenska")
    }

    @Test func copyProtectedVideos() async throws {
        StubProtocol.register("https://api.\(host)/video/drm", """
        {"programTitle": "Film", "rights": {"drmCopyProtection": true}, "videoReferences": [{"format": "hls", "url": "https://cdn.test/x.m3u8"}]}
        """)
        await #expect(throws: SVTError.copyProtected) { try await svt.stream(for: "drm") }
    }

    /// Against the real svtplay.se: `CMI_SVT_LIVE=1 swift test --filter live`
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CMI_SVT_LIVE"] != nil))
    func live() async throws {
        let svt = SVTPlay()
        let start = try await svt.startPage()
        #expect(!start.isEmpty)
        let letters = try await svt.allPrograms()
        #expect(letters.count > 20)
        let series = try #require(start.flatMap(\.items).first { if case .program = $0.kind { true } else { false } })
        guard case .program(let path) = series.kind else { return }
        let program = try await svt.program(path)
        let episode = try #require(program.seasons.first?.items.first?.videoID)
        let stream = try await svt.stream(for: episode)
        let hits = try await svt.search("agenda")
        #expect(hits.contains { $0.kind == .program(path: "/agenda") })
        print("live:", start.map(\.name), letters.count, "letters;", program.title, program.seasons.map(\.name), stream.url, "search:", hits.prefix(3).map(\.title))
    }
}
