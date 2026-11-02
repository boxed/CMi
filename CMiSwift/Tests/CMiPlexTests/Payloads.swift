// Realistic Plex JSON, trimmed. Shapes follow what plex.tv and Plex Media Server return with Accept: application/json.

enum Payloads {
    static let pinCreated = """
    {"id": 1234567, "code": "ABCD", "product": "CMi", "trusted": false, "qr": "https://plex.tv/api/v2/pins/qr/ABCD",
     "clientIdentifier": "client", "location": {"code": "SE", "country": "Sweden"}, "expiresIn": 900,
     "createdAt": "2026-10-29T10:00:00Z", "expiresAt": "2026-10-29T10:15:00Z", "authToken": null, "newRegistration": null}
    """

    static func pin(code: String, authToken: String?) -> String {
        """
        {"id": 1234567, "code": "\(code)", "product": "CMi", "trusted": false, "expiresIn": 600,
         "authToken": \(authToken.map { "\"\($0)\"" } ?? "null")}
        """
    }

    static func server(name: String, id: String, owned: Bool = true, accessToken: String, connections: [(uri: String, local: Bool, relay: Bool)]) -> String {
        let connections = connections.map { c in
            """
            {"protocol": "http", "address": "10.0.0.1", "port": 32400, "uri": "\(c.uri)", "local": \(c.local), "relay": \(c.relay), "IPv6": false}
            """
        }.joined(separator: ",")
        return """
        {"name": "\(name)", "product": "Plex Media Server", "productVersion": "1.40.2.8395", "platform": "Linux",
         "device": "PC", "clientIdentifier": "\(id)", "createdAt": "2020-01-01T00:00:00Z", "lastSeenAt": "2026-10-29T09:00:00Z",
         "provides": "server", "ownerId": null, "sourceTitle": null, "publicAddress": "81.0.0.1", "accessToken": "\(accessToken)",
         "owned": \(owned), "home": false, "synced": false, "relay": true, "presence": true, "httpsRequired": false,
         "publicAddressMatches": true, "dnsRebindingProtection": false, "natLoopbackSupported": true,
         "connections": [\(connections)]}
        """
    }

    static let player = """
    {"name": "iPhone", "product": "Plex for iOS", "productVersion": "8.30", "platform": "iOS", "device": "iPhone",
     "clientIdentifier": "phone-1", "provides": "client,player,pubsub-player", "accessToken": "phone-token", "owned": true,
     "presence": false, "connections": []}
    """

    static let sections = """
    {"MediaContainer": {"size": 4, "allowSync": false, "title1": "Plex Library", "Directory": [
      {"allowSync": true, "art": "/:/resources/movie-fanart.jpg", "composite": "/library/sections/1/composite/1700000000",
       "filters": true, "refreshing": false, "thumb": "/:/resources/movie.png", "key": "1", "type": "movie", "title": "Movies",
       "agent": "tv.plex.agents.movie", "scanner": "Plex Movie", "language": "en-US", "uuid": "a1", "updatedAt": 1700000000,
       "createdAt": 1600000000, "scannedAt": 1700000000, "content": true, "directory": true, "contentChangedAt": 123, "hidden": 0,
       "Location": [{"id": 1, "path": "/data/movies"}]},
      {"key": "2", "type": "show", "title": "TV Shows", "agent": "tv.plex.agents.series", "scanner": "Plex TV Series", "hidden": 0},
      {"key": "3", "type": "artist", "title": "Music", "agent": "tv.plex.agents.music", "hidden": 0},
      {"key": "4", "type": "photo", "title": "Photos", "agent": "com.plexapp.agents.none", "hidden": 0}
    ]}}
    """

    static let movies = """
    {"MediaContainer": {"size": 3, "allowSync": true, "librarySectionID": 1, "librarySectionTitle": "Movies", "viewGroup": "movie", "Metadata": [
      {"ratingKey": "101", "key": "/library/metadata/101", "guid": "plex://movie/1", "type": "movie", "title": "Alien",
       "year": 1979, "viewCount": 2, "lastViewedAt": 1690000000, "duration": 7020000, "addedAt": 1600000000,
       "Media": [{"id": 1, "duration": 7020000, "Part": [{"id": 1, "key": "/library/parts/1/1600000000/file.mkv", "file": "/data/movies/Alien.mkv"}]}]},
      {"ratingKey": "102", "key": "/library/metadata/102", "type": "movie", "title": "Brazil", "year": 1985, "viewOffset": 600000},
      {"ratingKey": "103", "key": "/library/metadata/103", "type": "movie", "title": "Untitled home video"}
    ]}}
    """

    static let shows = """
    {"MediaContainer": {"size": 2, "librarySectionID": 2, "viewGroup": "show", "Metadata": [
      {"ratingKey": "200", "key": "/library/metadata/200/children", "type": "show", "title": "The Wire", "year": 2002,
       "leafCount": 60, "viewedLeafCount": 13, "childCount": 5},
      {"ratingKey": "300", "key": "/library/metadata/300/children", "type": "show", "title": "Firefly", "year": 2002,
       "leafCount": 14, "viewedLeafCount": 14, "childCount": 1}
    ]}}
    """

    static let episodes = """
    {"MediaContainer": {"size": 4, "key": "200", "title2": "The Wire", "viewGroup": "episode", "Metadata": [
      {"ratingKey": "212", "type": "episode", "title": "Collateral Damage", "grandparentTitle": "The Wire", "parentIndex": 2, "index": 2,
       "originallyAvailableAt": "2003-06-08", "viewOffset": 1200000},
      {"ratingKey": "201", "type": "episode", "title": "The Target", "grandparentTitle": "The Wire", "parentIndex": 1, "index": 1,
       "originallyAvailableAt": "2002-06-02", "viewCount": 1},
      {"ratingKey": "202", "type": "episode", "title": "The Detail", "grandparentTitle": "The Wire", "parentIndex": 1, "index": 2,
       "originallyAvailableAt": "2002-06-09", "viewCount": 1, "viewOffset": 30000},
      {"ratingKey": "211", "type": "episode", "title": "Ebb Tide", "grandparentTitle": "The Wire", "parentIndex": "2", "index": "1"}
    ]}}
    """

    /// /library/onDeck: an episode in progress, the next episode of another show, a movie in progress,
    /// and a clip, which isn't something to continue.
    static let onDeck = """
    {"MediaContainer": {"size": 4, "mixedParents": true, "Metadata": [
        {"ratingKey": "212", "key": "/library/metadata/212", "type": "episode", "title": "Collateral Damage",
         "grandparentTitle": "The Wire", "parentIndex": 2, "index": 2, "viewOffset": 1200000, "lastViewedAt": 1761800000},
        {"ratingKey": "305", "key": "/library/metadata/305", "type": "episode", "title": "Bushwhacked",
         "grandparentTitle": "Firefly", "parentIndex": "1", "index": "3"},
        {"ratingKey": "102", "key": "/library/metadata/102", "type": "movie", "title": "Brazil", "year": 1985, "viewOffset": 3000000},
        {"ratingKey": "900", "key": "/library/metadata/900", "type": "clip", "title": "Trailer"}
    ]}}
    """

    /// /hubs/search: hubs per type, including ones CMi doesn't use.
    static let search = """
    {"MediaContainer": {"size": 4, "Hub": [
        {"hubIdentifier": "movie", "type": "movie", "title": "Movies", "size": 1, "Metadata": [
            {"ratingKey": "102", "type": "movie", "title": "Brazil", "year": 1985}]},
        {"hubIdentifier": "show", "type": "show", "title": "Shows", "size": 1, "Metadata": [
            {"ratingKey": "200", "type": "show", "title": "The Wire", "year": 2002, "leafCount": 60, "viewedLeafCount": 13}]},
        {"hubIdentifier": "episode", "type": "episode", "title": "Episodes", "size": 1, "Metadata": [
            {"ratingKey": "212", "type": "episode", "title": "Collateral Damage", "grandparentTitle": "The Wire", "parentIndex": 2, "index": 2, "viewOffset": 60000}]},
        {"hubIdentifier": "actor", "type": "actor", "title": "Actors", "size": 1, "Metadata": [{"ratingKey": "999", "type": "actor", "title": "Brazil Actor"}]},
        {"hubIdentifier": "collection", "type": "collection", "title": "Collections", "size": 0}
    ]}}
    """

    static let movieMetadata = """
    {"MediaContainer": {"size": 1, "Metadata": [
      {"ratingKey": "102", "type": "movie", "title": "Brazil", "year": 1985, "viewOffset": 600000, "duration": 8520000,
       "Media": [{"id": 7, "duration": 8520000, "container": "mkv",
         "Part": [{"id": 9, "key": "/library/parts/9/1600000000/file.mkv", "file": "/data/movies/Brazil.mkv", "size": 123}]}]}
    ]}}
    """
}
