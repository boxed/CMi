import Foundation

/// What's been watched on SVT Play, and how far. SVT Play doesn't know (there's no login), so it's kept in
/// `svtplay.json` in the CMi support folder.
public actor SVTProgress {
    public struct Entry: Codable, Sendable, Hashable {
        public var videoID: String
        /// Shown on the "continue watching" tile, e.g. "Agenda – Missnöjet mot (S)"
        public var title: String
        public var milliseconds: Int
        public var watched: Bool
        public var updated: Date
        /// The page of the program it's an episode of, e.g. "/agenda", so its next episode can be found.
        public var programPath: String?
    }

    private let file: URL
    private var entries: [String: Entry]

    public init(supportFolder: URL) {
        file = supportFolder.appending(path: "svtplay.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([String: Entry].self, from: Data(contentsOf: file))) ?? [:]
    }

    public func entry(for videoID: String) -> Entry? { entries[videoID] }

    public func setPosition(of videoID: String, title: String, programPath: String? = nil, milliseconds: Int) {
        var entry = entries[videoID] ?? Entry(videoID: videoID, title: title, milliseconds: 0, watched: false, updated: .now)
        entry.title = title
        entry.programPath = programPath ?? entry.programPath
        entry.milliseconds = milliseconds
        entry.updated = .now
        entries[videoID] = entry
        save()
    }

    public func markWatched(_ videoID: String, title: String, programPath: String? = nil) {
        var entry = entries[videoID] ?? Entry(videoID: videoID, title: title, milliseconds: 0, watched: false, updated: .now)
        entry.programPath = programPath ?? entry.programPath
        entry.watched = true
        entry.milliseconds = 0
        entry.updated = .now
        entries[videoID] = entry
        save()
    }

    /// Started but not finished, most recent first.
    public func inProgress(limit: Int = 10) -> [Entry] {
        Array(entries.values.filter { !$0.watched && $0.milliseconds > 0 }.sorted { $0.updated > $1.updated }.prefix(limit))
    }

    /// The programs something has been watched in, most recently watched first, with when that was.
    public func recentPrograms(limit: Int = 10) -> [(path: String, updated: Date)] {
        var latest: [String: Date] = [:]
        for entry in entries.values {
            guard let path = entry.programPath else { continue }
            latest[path] = max(latest[path] ?? .distantPast, entry.updated)
        }
        return Array(latest.sorted { $0.value > $1.value }.prefix(limit).map { (path: $0.key, updated: $0.value) })
    }

    /// The episode to continue with: the first one in progress, else the first unwatched one after the last
    /// watched one. Nil when that would just be the first episode, like for local and Plex shows.
    public func nextEpisode(in episodes: [SVTTeaser]) -> SVTTeaser? {
        func entry(_ episode: SVTTeaser) -> Entry? { episode.videoID.flatMap { entries[$0] } }
        func isWatched(_ episode: SVTTeaser) -> Bool { entry(episode)?.watched ?? false }

        var next = episodes.first { entry($0).map { !$0.watched && $0.milliseconds > 0 } ?? false }
        if next == nil, let lastWatched = episodes.lastIndex(where: isWatched) {
            next = episodes[(lastWatched + 1)...].first { !isWatched($0) }
        }
        return next == episodes.first ? nil : next
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(entries).write(to: file, options: .atomic)
    }
}
