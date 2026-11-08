import Foundation

extension Plex {
    /// The movie and show sections. Music, photos etc. are left out.
    public func sections() async throws -> [PlexSection] {
        try await get("/library/sections").directories.compactMap { d in
            guard let key = d.key else { return nil }
            let kind: PlexSection.Kind
            switch d.type {
            case "movie": kind = .movie
            case "show": kind = .show
            default: return nil
            }
            return PlexSection(id: key, title: d.title ?? "", kind: kind)
        }
    }

    /// Every movie or show in the section, watched or not, in server order.
    public func items(in section: PlexSection.ID) async throws -> [PlexItem] {
        try await get("/library/sections/\(section)/all").metadata.compactMap { m in
            guard let id = m.ratingKey else { return nil }
            switch m.type {
            case "movie":
                return PlexItem(id: id, title: m.title ?? "", year: m.year, kind: .movie, watched: m.viewCount > 0, unwatchedEpisodes: 0)
            case "show":
                let unwatched = max(0, m.leafCount - m.viewedLeafCount)
                return PlexItem(id: id, title: m.title ?? "", year: m.year, kind: .show, watched: unwatched == 0, unwatchedEpisodes: unwatched)
            default:
                return nil
            }
        }
    }

    /// All episodes of a show, sorted by season and episode number.
    public func episodes(ofShow ratingKey: String) async throws -> [PlexEpisode] {
        let episodes = try await get("/library/metadata/\(ratingKey)/allLeaves").metadata.compactMap(Self.episode)
        // Stable sort, episodes without a number keep their server order at the end of their season
        return episodes.enumerated().sorted { a, b in
            (a.element.season, a.element.index ?? .max, a.offset) < (b.element.season, b.element.index ?? .max, b.offset)
        }.map(\.element)
    }

    /// What to continue watching, most recently watched first (the server's order).
    public func onDeck() async throws -> [PlexOnDeckItem] {
        try await get("/library/onDeck").metadata.compactMap { m in
            guard let id = m.ratingKey else { return nil }
            switch m.type {
            case "episode":
                guard let episode = Self.episode(m) else { return nil }
                return PlexOnDeckItem(id: id, title: episode.showTitle, episode: episode, offset: m.viewOffset)
            case "movie":
                return PlexOnDeckItem(id: id, title: m.title ?? "", episode: nil, offset: m.viewOffset)
            default:
                return nil
            }
        }
    }

    /// Movies, shows and episodes matching `query` in every library, grouped by type like the server does.
    public func search(_ query: String, limit: Int = 20) async throws -> [PlexSearchResult] {
        let request = try serverRequest("/hubs/search", query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        return try await decode(MediaContainerResponse.self, request).hubs.flatMap { hub in
            hub.metadata.compactMap { m -> PlexSearchResult? in
                guard let id = m.ratingKey else { return nil }
                switch m.type ?? hub.type {
                case "movie":
                    return .movie(PlexItem(id: id, title: m.title ?? "", year: m.year, kind: .movie, watched: m.viewCount > 0, unwatchedEpisodes: 0))
                case "show":
                    let unwatched = max(0, m.leafCount - m.viewedLeafCount)
                    return .show(PlexItem(id: id, title: m.title ?? "", year: m.year, kind: .show, watched: unwatched == 0, unwatchedEpisodes: unwatched))
                case "episode":
                    return Self.episode(m).map { .episode($0) }
                default:
                    return nil   // people, collections, music etc.
                }
            }
        }
    }

    private static func episode(_ m: MetadataDTO) -> PlexEpisode? {
        guard let id = m.ratingKey else { return nil }
        return PlexEpisode(
            id: id,
            title: m.title ?? "",
            season: m.parentIndex ?? 0,
            index: m.index,
            aired: m.originallyAvailableAt,
            watched: m.viewCount > 0,
            offset: m.viewOffset,
            showTitle: m.grandparentTitle ?? ""
        )
    }

    public func playback(of ratingKey: String) async throws -> PlexPlayback {
        guard let server = store.server else { throw PlexError.notSignedIn }
        guard let metadata = try await get("/library/metadata/\(ratingKey)").metadata.first,
              let partKey = metadata.partKey
        else { throw PlexError.noMedia }
        let token = [URLQueryItem(name: "X-Plex-Token", value: server.token)]
        let subtitles = metadata.streams.filter { $0.streamType == 3 }.map { stream in
            PlexSubtitle(language: stream.language, selected: stream.selected, forced: stream.forced,
                         fileURL: stream.key.map { url(base: server.url, path: $0, query: token) }, format: stream.codec)
        }
        return PlexPlayback(streamURL: url(base: server.url, path: partKey, query: token), offset: metadata.viewOffset,
                            size: metadata.partSize, showID: metadata.grandparentRatingKey, subtitles: subtitles)
    }

    /// Downloads subtitles that are in a file of their own into `folder`, named so VLC knows the format
    /// (Plex's URL doesn't say). Returns the file.
    public func download(_ subtitle: PlexSubtitle, to folder: URL) async throws -> URL {
        guard subtitle.isDownloadable, let url = subtitle.fileURL else { throw PlexError.noMedia }
        let data = try await data(for: request(url))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = url.path.split(separator: "/").last.map(String.init) ?? "subtitles"
        let file = folder.appending(path: "\(name).\(subtitle.format ?? "srt")", directoryHint: .notDirectory)
        try data.write(to: file)
        return file
    }

    /// Reports the playback position. Failures are ignored, the next report will catch up.
    public func reportProgress(of ratingKey: String, milliseconds: Int) async {
        _ = try? await data(for: serverRequest("/:/progress", query: [
            URLQueryItem(name: "key", value: ratingKey),
            URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library"),
            URLQueryItem(name: "time", value: String(milliseconds)),
            URLQueryItem(name: "state", value: "playing"),
        ]))
    }

    /// Marks as watched.
    public func scrobble(_ ratingKey: String) async {
        _ = try? await data(for: serverRequest("/:/scrobble", query: [
            URLQueryItem(name: "key", value: ratingKey),
            URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library"),
        ]))
    }

    func serverRequest(_ path: String, query: [URLQueryItem] = []) throws -> URLRequest {
        guard let server = store.server else { throw PlexError.notSignedIn }
        return try request(url(base: server.url, path: path, query: query), token: server.token)
    }

    func get(_ path: String) async throws -> MediaContainerResponse {
        try await decode(MediaContainerResponse.self, serverRequest(path))
    }
}
