import Foundation

public struct PlexConnection: Sendable, Hashable {
    public var uri: String
    public var local: Bool
    public var relay: Bool

    public init(uri: String, local: Bool, relay: Bool) {
        self.uri = uri
        self.local = local
        self.relay = relay
    }
}

public struct PlexServer: Sendable, Hashable, Identifiable {
    /// The server's clientIdentifier.
    public var id: String
    public var name: String
    public var owned: Bool
    /// The token for this server (not the account token), which is what gets saved on sign in.
    public var accessToken: String
    public var connections: [PlexConnection]

    public init(id: String, name: String, owned: Bool, accessToken: String, connections: [PlexConnection]) {
        self.id = id
        self.name = name
        self.owned = owned
        self.accessToken = accessToken
        self.connections = connections
    }

    /// Local first, then remote, then Plex's relay.
    var connectionsInProbeOrder: [PlexConnection] {
        connections.enumerated().sorted { a, b in
            let ka = (a.element.relay ? 1 : 0, a.element.local ? 0 : 1, a.offset)
            let kb = (b.element.relay ? 1 : 0, b.element.local ? 0 : 1, b.offset)
            return ka < kb
        }.map(\.element)
    }
}

public struct PlexPin: Sendable, Hashable {
    public var id: Int
    public var code: String
    public var created: Date

    public init(id: Int, code: String, created: Date) {
        self.id = id
        self.code = code
        self.created = created
    }
}

public struct PlexSection: Sendable, Hashable, Identifiable {
    /// The section key.
    public var id: String
    public var title: String
    public var kind: Kind

    public enum Kind: Sendable { case movie, show }
}

/// An entry in a section: a movie or a show.
public struct PlexItem: Sendable, Hashable, Identifiable {
    /// The ratingKey.
    public var id: String
    public var title: String
    public var year: Int?
    public var kind: Kind
    /// Movies: viewCount > 0. Shows: every episode watched.
    public var watched: Bool
    /// Shows: leafCount - viewedLeafCount. Always 0 for movies.
    public var unwatchedEpisodes: Int

    public enum Kind: Sendable { case movie, show }
}

public struct PlexEpisode: Sendable, Hashable, Identifiable {
    /// The ratingKey.
    public var id: String
    public var title: String
    public var season: Int
    public var index: Int?
    /// originallyAvailableAt, e.g. "2008-01-20".
    public var aired: String?
    public var watched: Bool
    /// Resume position in milliseconds.
    public var offset: Int
    public var showTitle: String

    public var inProgress: Bool { offset > 0 && !watched }

    /// The episode to continue with: the first one in progress, otherwise the first unwatched one.
    /// nil when that is the very first episode, since then there's nothing to "continue".
    public static func next(in episodes: [PlexEpisode]) -> PlexEpisode? {
        let next = episodes.first(where: \.inProgress) ?? episodes.first { !$0.watched }
        return next == episodes.first ? nil : next
    }
}

/// Something to continue watching, from the server's On Deck: the episode in progress or up next for each
/// show being watched, or a movie in progress.
public struct PlexOnDeckItem: Sendable, Hashable, Identifiable {
    /// The ratingKey of the episode or movie, for `playback(of:)`.
    public var id: String
    /// The show's title for episodes, the movie's title for movies.
    public var title: String
    /// Set for episodes.
    public var episode: PlexEpisode?
    /// Milliseconds already watched.
    public var offset: Int

    public init(id: String, title: String, episode: PlexEpisode?, offset: Int) {
        self.id = id
        self.title = title
        self.episode = episode
        self.offset = offset
    }
}

/// A search hit: something to play, or a show to open.
public enum PlexSearchResult: Sendable, Hashable {
    case movie(PlexItem)
    case show(PlexItem)
    case episode(PlexEpisode)
}

public struct PlexPlayback: Sendable {
    /// The media part URL with the token in the query, since the player can't send headers.
    public var streamURL: URL
    /// Resume position in milliseconds.
    public var offset: Int
}

public enum PlexError: Error, Sendable, Equatable {
    case notSignedIn
    case pinExpired
    case httpStatus(Int)
    case invalidResponse
    case noMedia
}
