import Foundation

// Plex JSON omits fields freely and isn't consistent about numbers vs strings, so everything is decoded leniently.

extension KeyedDecodingContainer {
    func lenientInt(_ key: Key) -> Int? {
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return Int(v) }
        if let v = try? decodeIfPresent(String.self, forKey: key) { return Int(v) }
        return nil
    }

    func lenientString(_ key: Key) -> String? {
        if let v = try? decodeIfPresent(String.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return String(v) }
        return nil
    }

    func lenientBool(_ key: Key) -> Bool? {
        if let v = try? decodeIfPresent(Bool.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v != 0 }
        if let v = try? decodeIfPresent(String.self, forKey: key) { return ["1", "true"].contains(v.lowercased()) }
        return nil
    }

    /// Decodes an array, skipping elements that fail to decode.
    func lenientArray<T: Decodable>(_ type: T.Type, _ key: Key) -> [T] {
        guard var container = try? nestedUnkeyedContainer(forKey: key) else { return [] }
        var result: [T] = []
        while !container.isAtEnd {
            if let v = try? container.decode(T.self) {
                result.append(v)
            } else {
                _ = try? container.decode(Skip.self)
            }
        }
        return result
    }
}

private struct Skip: Decodable {
    init(from decoder: Decoder) {}  // succeeds for any value, so the unkeyed container moves past it
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

// MARK: - plex.tv

struct PinDTO: Decodable {
    var id: Int
    var code: String
    var authToken: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.lenientInt(AnyKey("id")), let code = c.lenientString(AnyKey("code")) else {
            throw PlexError.invalidResponse
        }
        self.id = id
        self.code = code
        authToken = c.lenientString(AnyKey("authToken")).flatMap { $0.isEmpty ? nil : $0 }
    }
}

struct ResourceDTO: Decodable {
    var server: PlexServer?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let provides = (c.lenientString(AnyKey("provides")) ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard provides.contains("server"),
              let id = c.lenientString(AnyKey("clientIdentifier")),
              let token = c.lenientString(AnyKey("accessToken"))
        else { return }
        server = PlexServer(
            id: id,
            name: c.lenientString(AnyKey("name")) ?? id,
            owned: c.lenientBool(AnyKey("owned")) ?? false,
            accessToken: token,
            connections: c.lenientArray(ConnectionDTO.self, AnyKey("connections")).map(\.connection)
        )
    }
}

struct ConnectionDTO: Decodable {
    var connection: PlexConnection

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let uri = c.lenientString(AnyKey("uri")) else { throw PlexError.invalidResponse }
        connection = PlexConnection(uri: uri, local: c.lenientBool(AnyKey("local")) ?? false, relay: c.lenientBool(AnyKey("relay")) ?? false)
    }
}

// MARK: - Media server

struct MediaContainerResponse: Decodable {
    var directories: [DirectoryDTO]
    var metadata: [MetadataDTO]
    /// Search results, grouped by type
    var hubs: [HubDTO]

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: AnyKey.self)
        let c = try root.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("MediaContainer"))
        directories = c.lenientArray(DirectoryDTO.self, AnyKey("Directory"))
        metadata = c.lenientArray(MetadataDTO.self, AnyKey("Metadata"))
        hubs = c.lenientArray(HubDTO.self, AnyKey("Hub"))
    }
}

struct HubDTO: Decodable {
    var type: String?
    var metadata: [MetadataDTO]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        type = c.lenientString(AnyKey("type"))
        metadata = c.lenientArray(MetadataDTO.self, AnyKey("Metadata"))
    }
}

struct DirectoryDTO: Decodable {
    var key: String?
    var type: String?
    var title: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        key = c.lenientString(AnyKey("key"))
        type = c.lenientString(AnyKey("type"))
        title = c.lenientString(AnyKey("title"))
    }
}

struct MetadataDTO: Decodable {
    var ratingKey: String?
    var type: String?
    var title: String?
    var year: Int?
    var viewCount: Int
    var leafCount: Int
    var viewedLeafCount: Int
    var viewOffset: Int
    var parentIndex: Int?
    var index: Int?
    var originallyAvailableAt: String?
    var grandparentTitle: String?
    var grandparentRatingKey: String?
    var partKey: String?
    var partSize: Int?
    var streams: [StreamDTO]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        ratingKey = c.lenientString(AnyKey("ratingKey"))
        type = c.lenientString(AnyKey("type"))
        title = c.lenientString(AnyKey("title"))
        year = c.lenientInt(AnyKey("year"))
        viewCount = c.lenientInt(AnyKey("viewCount")) ?? 0
        leafCount = c.lenientInt(AnyKey("leafCount")) ?? 0
        viewedLeafCount = c.lenientInt(AnyKey("viewedLeafCount")) ?? 0
        viewOffset = c.lenientInt(AnyKey("viewOffset")) ?? 0
        parentIndex = c.lenientInt(AnyKey("parentIndex"))
        index = c.lenientInt(AnyKey("index"))
        originallyAvailableAt = c.lenientString(AnyKey("originallyAvailableAt"))
        grandparentTitle = c.lenientString(AnyKey("grandparentTitle"))
        grandparentRatingKey = c.lenientString(AnyKey("grandparentRatingKey"))
        let part = c.lenientArray(MediaDTO.self, AnyKey("Media")).first?.parts.first { $0.key != nil }
        partKey = part?.key
        partSize = part?.size
        streams = part?.streams ?? []
    }
}

struct MediaDTO: Decodable {
    var parts: [PartDTO]

    init(from decoder: Decoder) throws {
        parts = try decoder.container(keyedBy: AnyKey.self).lenientArray(PartDTO.self, AnyKey("Part"))
    }
}

struct PartDTO: Decodable {
    var key: String?
    /// In bytes.
    var size: Int?
    var streams: [StreamDTO]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        key = c.lenientString(AnyKey("key"))
        size = c.lenientInt(AnyKey("size"))
        streams = c.lenientArray(StreamDTO.self, AnyKey("Stream"))
    }
}

/// A video, audio or subtitle stream of a part. Subtitles in their own file have a key to download them from.
struct StreamDTO: Decodable {
    var streamType: Int?
    var key: String?
    var codec: String?
    var language: String?
    var selected: Bool
    var forced: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        streamType = c.lenientInt(AnyKey("streamType"))
        key = c.lenientString(AnyKey("key"))
        codec = c.lenientString(AnyKey("codec"))
        language = c.lenientString(AnyKey("language"))
        selected = c.lenientBool(AnyKey("selected")) ?? false
        forced = c.lenientBool(AnyKey("forced")) ?? false
    }
}
