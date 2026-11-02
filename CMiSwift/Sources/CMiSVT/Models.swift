import Foundation

/// Something listed on SVT Play: a video to play, or a program with episodes.
public struct SVTTeaser: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        /// An episode, film, documentary or clip.
        case video(id: String)
        /// A series or other program, with its own page of episodes.
        case program(path: String)
    }

    /// The page path on svtplay.se, e.g. "/video/jMdmAp9/nazistdonatorn/1-att-veta-sanningen" or "/rapport".
    public var path: String
    public var title: String
    /// e.g. "Idag 02:00 • 28 min"
    public var subtitle: String?
    public var kind: Kind

    public var id: String { path }

    public init(path: String, title: String, subtitle: String? = nil) {
        self.path = path
        self.title = title
        self.subtitle = subtitle
        kind = Self.videoID(inPath: path).map { .video(id: $0) } ?? .program(path: path)
    }

    /// The video id in "/video/<id>/…" and "/klipp/<id>/…" paths.
    static func videoID(inPath path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "video" || parts[0] == "klipp" else { return nil }
        return String(parts[1])
    }

    public var videoID: String? {
        if case .video(let id) = kind { return id }
        return nil
    }
}

/// A named list of teasers: a row on the start page, a season, or a letter of the A–Ö list.
public struct SVTSection: Sendable, Hashable {
    public var name: String
    public var items: [SVTTeaser]

    public init(name: String, items: [SVTTeaser]) {
        self.name = name
        self.items = items
    }
}

/// A program's page: its seasons (or other lists of episodes), in the order the site shows them.
public struct SVTProgram: Sendable, Hashable {
    public var title: String
    public var seasons: [SVTSection]
}

public struct SVTStream: Sendable {
    public var url: URL
    /// "Program – Episode"
    public var title: String
}

public enum SVTError: Error, Equatable, LocalizedError {
    case httpStatus(Int)
    /// The page didn't have the data CMi reads; svtplay.se has probably changed.
    case unexpectedPage
    case copyProtected
    case noStream

    public var errorDescription: String? {
        switch self {
        case .httpStatus(let status): "SVT Play answered with HTTP \(status)"
        case .unexpectedPage: "SVT Play's pages have changed, CMi needs an update to read them"
        case .copyProtected: "This one is copy protected and can only be watched in SVT's own apps"
        case .noStream: "SVT Play has no stream for this right now"
        }
    }
}
