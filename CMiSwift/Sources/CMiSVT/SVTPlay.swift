import Foundation

/// Browsing SVT Play and finding the stream for a video. No account needed.
public struct SVTPlay: Sendable {
    let site: URL
    let videoAPI: URL
    let session: URLSession

    public init(site: URL = URL(string: "https://www.svtplay.se")!,
                videoAPI: URL = URL(string: "https://api.svt.se/video")!,
                session: URLSession = .shared) {
        self.site = site
        self.videoAPI = videoAPI
        self.session = session
    }

    /// The lists on the start page ("Vi rekommenderar", "Populärt", …), in page order.
    public func startPage() async throws -> [SVTSection] {
        let modules = try await page("/").startForSvtPlay?.modules?.items ?? []
        return modules.compactMap { module in
            guard let selection = module.selection, let name = selection.name, !name.isEmpty else { return nil }
            let items = selection.teasers
            return items.isEmpty ? nil : SVTSection(name: name, items: items)
        }
    }

    /// Every program, by letter (the "Program A–Ö" page).
    public func allPrograms() async throws -> [SVTSection] {
        guard let selections = try await page("/program").programAtillO?.selections else { throw SVTError.unexpectedPage }
        return selections.compactMap { selection in
            let items = selection.teasers
            return items.isEmpty ? nil : SVTSection(name: selection.name ?? "", items: items)
        }
    }

    /// A program's seasons. Programs without seasons get their lists of episodes instead; clips, upcoming
    /// and related programs are left out.
    public func program(_ path: String) async throws -> SVTProgram {
        guard let details = try await page(path).detailsPageByPath else { throw SVTError.unexpectedPage }
        let lists = (details.modules ?? []).compactMap { module -> (id: String, type: String?, section: SVTSection)? in
            guard let id = module.id, let selection = module.selection else { return nil }
            let items = selection.teasers
            guard !items.isEmpty else { return nil }
            return (id, selection.selectionType, SVTSection(name: selection.name ?? "", items: items))
        }
        let seasons = lists.filter { $0.type == "season" }
        let episodes = seasons.isEmpty
            ? lists.filter { list in !["related", "upcoming"].contains(list.id) && !list.id.hasPrefix("details") && !list.id.contains("clips") }
            : seasons
        return SVTProgram(title: details.item?.name ?? details.heading ?? "", seasons: Self.inViewingOrder(episodes.map(\.section)))
    }

    /// The site lists seasons newest first. When they're all numbered ("Säsong 2"), put them in viewing order.
    static func inViewingOrder(_ seasons: [SVTSection]) -> [SVTSection] {
        let numbers = seasons.map { $0.name.split(separator: " ").last.flatMap { Int($0) } }
        guard !numbers.contains(nil) else { return seasons }
        return zip(seasons, numbers).sorted { $0.1! < $1.1! }.map(\.0)
    }

    /// Programs and videos matching `query`, best first, like the search on svtplay.se.
    public func search(_ query: String) async throws -> [SVTTeaser] {
        var components = URLComponents()
        components.path = "/sok"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let path = components.string else { return [] }
        guard let search = try await page(path).searchPage else { throw SVTError.unexpectedPage }
        return search.teasers
    }

    /// The HLS stream for a video. Throws `SVTError.copyProtected` for the few that need DRM.
    public func stream(for videoID: String) async throws -> SVTStream {
        let video = try JSONDecoder().decode(VideoDTO.self, from: try await get(videoAPI.appending(path: videoID)))
        if video.rights?.drmCopyProtection == true { throw SVTError.copyProtected }
        let references = video.videoReferences ?? []
        // Plain "hls" has every quality and the subtitles; the "-full"/hbbtv variants are for other devices.
        guard let string = (references.first { $0.format == "hls" } ?? references.first { $0.url?.contains(".m3u8") == true })?.url,
              let url = URL(string: string)
        else { throw SVTError.noStream }
        let title = [video.programTitle, video.episodeTitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " – ")
        let subtitles = video.subtitleReferences?.first { $0.type == "subtitle" }?.label
        return SVTStream(url: url, title: title, defaultSubtitles: subtitles)
    }

    // MARK: HTTP

    func page(_ path: String) async throws -> PageData {
        guard let url = URL(string: path, relativeTo: site)?.absoluteURL else { throw SVTError.unexpectedPage }
        let data = try await get(url)
        return try PageData.parse(html: String(decoding: data, as: UTF8.self))
    }

    private func get(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: 20))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SVTError.httpStatus(http.statusCode)
        }
        return data
    }
}
