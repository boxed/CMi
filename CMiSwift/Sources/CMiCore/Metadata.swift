import Foundation

/// A show search result from TVmaze.
public struct ShowInfo: Sendable, Hashable {
    public var id: Int
    public var name: String
    /// Plain text (HTML tags stripped).
    public var overview: String
    public var premiered: Day?

    public init(id: Int, name: String, overview: String = "", premiered: Day? = nil) {
        self.id = id
        self.name = name
        self.overview = overview
        self.premiered = premiered
    }
}

/// An episode from TVmaze.
public struct EpisodeInfo: Sendable, Hashable {
    public var id: Int
    public var name: String
    public var season: Int?
    /// Nil for specials.
    public var number: Int?
    public var airdate: Day?
    /// Plain text (HTML tags stripped).
    public var overview: String

    public init(id: Int, name: String, season: Int?, number: Int?, airdate: Day? = nil, overview: String = "") {
        self.id = id
        self.name = name
        self.season = season
        self.number = number
        self.airdate = airdate
        self.overview = overview
    }
}

/// A title from IMDb's search suggestions (movies, but also series, games etc).
public struct TitleInfo: Sendable, Hashable {
    /// e.g. "tt0371746"
    public var imdbID: String
    public var title: String
    public var year: Int?
    /// IMDb's `qid`: "movie", "tvSeries", "videoGame", …
    public var kind: String

    public init(imdbID: String, title: String, year: Int? = nil, kind: String = "movie") {
        self.imdbID = imdbID
        self.title = title
        self.year = year
        self.kind = kind
    }
}

/// Metadata lookups, injectable for tests.
public protocol MetadataProvider: Sendable {
    /// TVmaze show search, best match first.
    func searchShows(_ name: String) async throws -> [ShowInfo]
    /// All (non special) episodes of a TVmaze show.
    func episodes(ofShow id: Int) async throws -> [EpisodeInfo]
    /// IMDb title search, best match first. People are left out.
    func searchTitles(_ title: String) async throws -> [TitleInfo]
}

public struct MetadataError: Error, CustomStringConvertible {
    public var url: URL
    public var statusCode: Int
    public var description: String { "HTTP \(statusCode) from \(url)" }
}

/// The real web APIs: TVmaze (https://www.tvmaze.com/api) and IMDb's search suggestion endpoint.
/// Neither needs an API key.
public struct LiveMetadata: MetadataProvider {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func searchShows(_ name: String) async throws -> [ShowInfo] {
        let results = try await get("https://api.tvmaze.com/search/shows?q=\(percentEncoded(name))", as: [TVmazeSearchResult].self)
        return results.map {
            ShowInfo(id: $0.show.id, name: $0.show.name, overview: stripHTML($0.show.summary),
                     premiered: $0.show.premiered.flatMap { Day($0) })
        }
    }

    public func episodes(ofShow id: Int) async throws -> [EpisodeInfo] {
        try await get("https://api.tvmaze.com/shows/\(id)/episodes", as: [TVmazeEpisode].self).map {
            EpisodeInfo(id: $0.id, name: $0.name ?? "", season: $0.season, number: $0.number,
                        airdate: $0.airdate.flatMap { Day($0) }, overview: stripHTML($0.summary))
        }
    }

    public func searchTitles(_ title: String) async throws -> [TitleInfo] {
        let url = "https://v3.sg.media-imdb.com/suggestion/x/\(percentEncoded(title.lowercased())).json"
        return try await get(url, as: IMDbSuggestions.self).d?.compactMap { item in
            // People don't have a qid
            guard let kind = item.qid, let title = item.l else { return nil }
            return TitleInfo(imdbID: item.id, title: title, year: item.y, kind: kind)
        } ?? []
    }

    private func get<T: Decodable>(_ urlString: String, as type: T.Type) async throws -> T {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: 10))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MetadataError(url: url, statusCode: http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// Like Python's `urllib.parse.quote`: everything but ASCII letters, digits and `_.-~/` is percent encoded.
private func percentEncoded(_ s: String) -> String {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-~/")
    return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
}

func stripHTML(_ s: String?) -> String {
    (s ?? "").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - JSON

private struct TVmazeSearchResult: Decodable {
    struct Show: Decodable {
        var id: Int
        var name: String
        var summary: String?
        var premiered: String?
    }
    var show: Show
}

private struct TVmazeEpisode: Decodable {
    var id: Int
    var name: String?
    var season: Int?
    var number: Int?
    var airdate: String?
    var summary: String?
}

private struct IMDbSuggestions: Decodable {
    struct Item: Decodable {
        var id: String
        var l: String?
        var qid: String?
        var y: Int?
    }
    var d: [Item]?
}
