import Foundation
import os

let logger = Logger(subsystem: "CMi", category: "CMiCore")

/// The CMi library database (`cmi.db`), in the same format as the old Django app so both can use the file.
///
/// Thread safe (internally serialized); fine to call from the main thread, queries are fast.
/// Reads return empty results and writes do nothing if SQLite fails; errors are logged.
public final class Database: @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()

    /// Opens the database, creating the file, its folder and any missing tables.
    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        connection = try SQLiteConnection(path: url.path(percentEncoded: false))
        try DjangoSchema.install(on: connection)
    }

    // MARK: - Categories and shows

    /// Sorted by name.
    public func categories() -> [Category] {
        query("SELECT id, name FROM tvshows_category ORDER BY name, id") { Category(id: $0.int64(0), name: $0.string(1)) }
    }

    /// The shows in a category (nil = uncategorized) that have something to watch, sorted by `titleSortKey`.
    public func shows(in category: Int64?) -> [Show] {
        query("""
            SELECT \(Self.showColumns) FROM tvshows_show s
            WHERE s.category_id IS ? AND EXISTS (
                SELECT 1 FROM tvshows_episode e
                WHERE e.show_id = s.id AND e.filepath != '' AND (s.auto_erase = 0 OR e.watched = 0))
            """, [category], Show.init(row:))
        .sorted { (titleSortKey($0.name), $0.name) < (titleSortKey($1.name), $1.name) }
    }

    public func show(_ id: Int64) -> Show? {
        query("SELECT \(Self.showColumns) FROM tvshows_show s WHERE s.id = ?", [id], Show.init(row:)).first
    }

    /// The show episode files named `canonicalName` belong to.
    public func show(canonicalName: String) -> Show? {
        query("SELECT \(Self.showColumns) FROM tvshows_show s WHERE s.canonical_name = ? ORDER BY s.id",
              [canonicalName], Show.init(row:)).first
    }

    // MARK: - Episodes

    /// The episodes that have a file; for auto erase shows only the unwatched ones. Ordered by season, episode, aired.
    public func watchableEpisodes(of show: Int64) -> [Episode] {
        query("""
            SELECT \(Self.episodeColumns) FROM tvshows_episode e JOIN tvshows_show s ON s.id = e.show_id
            WHERE e.show_id = ? AND e.filepath != '' AND (s.auto_erase = 0 OR e.watched = 0)
            ORDER BY e.season, e.episode, e.aired, e.id
            """, [show], Episode.init(row:))
    }

    /// Unwatched episodes that have a file.
    public func unwatchedEpisodeCount(of show: Int64) -> Int {
        count("SELECT COUNT(*) FROM tvshows_episode WHERE show_id = ? AND filepath != '' AND watched = 0", [show])
    }

    /// The episode to suggest continuing with: the watchable episode watched longest ago (never watched counts
    /// as longest ago), in season order. Nil if that's just the first watchable episode anyway.
    public func nextEpisode(of show: Int64) -> Episode? {
        let episodes = watchableEpisodes(of: show)
        guard let first = episodes.first,
              let next = episodes.enumerated().min(by: { ($0.element.watchedAt, $0.offset) < ($1.element.watchedAt, $1.offset) })?.element,
              next.id != first.id else { return nil }
        return next
    }

    /// For the home screen tile ("N new / M total"): episodes with a file in shows of the category (nil = uncategorized).
    public func episodeCounts(in category: Int64?) -> (new: Int, total: Int) {
        let rows = query("""
            SELECT COUNT(*), COALESCE(SUM(e.watched = 0), 0) FROM tvshows_episode e JOIN tvshows_show s ON s.id = e.show_id
            WHERE s.category_id IS ? AND e.filepath != ''
            """, [category]) { (new: $0.int(1), total: $0.int(0)) }
        return rows.first ?? (0, 0)
    }

    public func episode(_ id: Int64) -> Episode? {
        query("SELECT \(Self.episodeColumns) FROM tvshows_episode e WHERE e.id = ?", [id], Episode.init(row:)).first
    }

    /// Every episode, in show, season, episode order.
    public func allEpisodes() -> [Episode] {
        query("SELECT \(Self.episodeColumns) FROM tvshows_episode e ORDER BY e.show_id, e.season, e.episode, e.aired, e.id",
              [], Episode.init(row:))
    }

    public func setEpisodePosition(_ id: Int64, milliseconds: Double) {
        run("UPDATE tvshows_episode SET position = ? WHERE id = ?", [milliseconds, id])
    }

    /// Played to the end: marks it watched, counts the viewing and rewinds it.
    public func episodeEnded(_ id: Int64) {
        run("UPDATE tvshows_episode SET watched = 1, watched_count = watched_count + 1, position = 0, watched_at = ? WHERE id = ?",
            [DjangoDateTime.string(from: Date()), id])
    }

    /// Adds an episode (with Django's defaults for the other columns) and returns its id.
    @discardableResult
    public func insertEpisode(show: Int64, season: Int, episode: Int = 0, aired: Day? = nil, name: String = "",
                              filepath: String = "", watched: Bool = false) -> Int64? {
        insert("""
            INSERT INTO tvshows_episode (name, season, episode, aired, description, watched, position, filepath, watched_count, watched_at, show_id)
            VALUES (?, ?, ?, ?, NULL, ?, 0, ?, 0, ?, ?)
            """, [name, season, episode, aired, watched, filepath, DjangoDateTime.string(from: DjangoDateTime.neverWatched), show])
    }

    /// Points the episode identified by show, season, episode and aired at `filepath`, creating it if needed
    /// (Django's `get_or_create`).
    func setEpisodeFile(show: Int64, season: Int, episode: Int, aired: Day?, filepath: String) {
        let existing = query("""
            SELECT id FROM tvshows_episode WHERE show_id = ? AND season = ? AND episode = ? AND aired IS ? ORDER BY id LIMIT 1
            """, [show, season, episode, aired]) { $0.int64(0) }
        if let id = existing.first {
            setEpisodeFilepath(id, filepath)
        } else {
            insertEpisode(show: show, season: season, episode: episode, aired: aired, filepath: filepath)
        }
    }

    func setEpisodeFilepath(_ id: Int64, _ filepath: String) {
        run("UPDATE tvshows_episode SET filepath = ? WHERE id = ?", [filepath, id])
    }

    func setEpisodeInfo(_ id: Int64, name: String, description: String) {
        run("UPDATE tvshows_episode SET name = ?, description = ? WHERE id = ?", [name, description, id])
    }

    /// Watched episodes that still have a file and belong to auto erase shows.
    func watchedAutoEraseEpisodes() -> [Episode] {
        query("""
            SELECT \(Self.episodeColumns) FROM tvshows_episode e JOIN tvshows_show s ON s.id = e.show_id
            WHERE e.watched = 1 AND e.filepath != '' AND s.auto_erase = 1
            """, [], Episode.init(row:))
    }

    /// Episodes with a file but no name yet.
    func episodesMissingName() -> [Episode] {
        query("SELECT \(Self.episodeColumns) FROM tvshows_episode e WHERE e.name = '' AND e.filepath != '' ORDER BY e.id",
              [], Episode.init(row:))
    }

    // MARK: - Movies

    /// Sorted by name.
    public func unwatchedMovies() -> [Movie] {
        query("SELECT \(Self.movieColumns) FROM movies_movie WHERE watched = 0 ORDER BY name, id", [], Movie.init(row:))
    }

    public func allMovies() -> [Movie] {
        query("SELECT \(Self.movieColumns) FROM movies_movie ORDER BY name, id", [], Movie.init(row:))
    }

    /// For the home screen tile ("N new / M total").
    public func movieCounts() -> (new: Int, total: Int) {
        query("SELECT COUNT(*), COALESCE(SUM(watched = 0), 0) FROM movies_movie") { (new: $0.int(1), total: $0.int(0)) }.first ?? (0, 0)
    }

    public func movie(_ id: Int64) -> Movie? {
        query("SELECT \(Self.movieColumns) FROM movies_movie WHERE id = ?", [id], Movie.init(row:)).first
    }

    public func setMoviePosition(_ id: Int64, milliseconds: Double) {
        run("UPDATE movies_movie SET position = ? WHERE id = ?", [milliseconds, id])
    }

    /// Marks it watched. Like the Django app, the position is left as is.
    public func movieEnded(_ id: Int64) {
        run("UPDATE movies_movie SET watched = 1 WHERE id = ?", [id])
    }

    @discardableResult
    public func insertMovie(name: String, aired: String = "", filepath: String, watched: Bool = false) -> Int64? {
        insert("INSERT INTO movies_movie (name, aired, watched, position, filepath) VALUES (?, ?, ?, 0, ?)",
               [name, aired, watched, filepath])
    }

    func deleteMovie(_ id: Int64) {
        run("DELETE FROM movies_movie WHERE id = ?", [id])
    }

    // MARK: - Suggested shows

    /// The suggestions that haven't been ignored, sorted by name.
    public func suggestedShows() -> [SuggestedShow] {
        query("SELECT id, name, ignored FROM tvshows_suggestedshow WHERE ignored = 0 ORDER BY name, id", [], SuggestedShow.init(row:))
    }

    public func suggestedShow(_ id: Int64) -> SuggestedShow? {
        query("SELECT id, name, ignored FROM tvshows_suggestedshow WHERE id = ?", [id], SuggestedShow.init(row:)).first
    }

    /// Whether there's a suggestion with this name, ignored or not.
    func hasSuggestedShow(named name: String) -> Bool {
        count("SELECT COUNT(*) FROM tvshows_suggestedshow WHERE name = ?", [name]) > 0
    }

    public func ignoreSuggestedShow(_ id: Int64) {
        run("UPDATE tvshows_suggestedshow SET ignored = 1 WHERE id = ?", [id])
    }

    /// Returns nil if there already is a suggestion with that name.
    @discardableResult
    public func insertSuggestedShow(name: String) -> Int64? {
        insert("INSERT OR IGNORE INTO tvshows_suggestedshow (name, ignored) VALUES (?, 0)", [name])
    }

    func deleteSuggestedShow(_ id: Int64) {
        run("DELETE FROM tvshows_suggestedshow WHERE id = ?", [id])
    }

    // MARK: - Inserting shows and categories

    /// Adds a show and returns its id, or nil if there already is one with that name (names are unique).
    @discardableResult
    public func insertShow(name: String, description: String = "", canonicalName: String? = nil, autoErase: Bool = true,
                           ended: Bool = false, category: Int64? = nil) -> Int64? {
        insert("""
            INSERT OR IGNORE INTO tvshows_show (name, description, canonical_name, auto_erase, source, ended, category_id)
            VALUES (?, ?, ?, ?, '', ?, ?)
            """, [name, description, canonicalName ?? canonicalFormat(name), autoErase, ended, category])
    }

    @discardableResult
    public func insertCategory(name: String) -> Int64? {
        insert("INSERT INTO tvshows_category (name) VALUES (?)", [name])
    }

    // MARK: - Plumbing

    private static let showColumns = "s.id, s.name, s.description, s.canonical_name, s.auto_erase, s.source, s.ended, s.category_id"
    private static let episodeColumns = "e.id, e.show_id, e.name, e.season, e.episode, e.aired, e.description, e.watched, e.position, e.filepath, e.watched_count, e.watched_at"
    private static let movieColumns = "id, name, aired, watched, position, filepath"

    private func locked<T>(_ fallback: T, _ body: () throws -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        do {
            return try body()
        } catch {
            logger.error("Database error: \(String(describing: error), privacy: .public)")
            return fallback
        }
    }

    private func query<T>(_ sql: String, _ arguments: [any SQLBindable] = [], _ map: (Row) -> T) -> [T] {
        locked([]) { try connection.query(sql, arguments, map) }
    }

    private func count(_ sql: String, _ arguments: [any SQLBindable]) -> Int {
        query(sql, arguments) { $0.int(0) }.first ?? 0
    }

    @discardableResult
    private func run(_ sql: String, _ arguments: [any SQLBindable]) -> Int {
        locked(0) { try connection.run(sql, arguments) }
    }

    /// The new row's id, or nil if nothing was inserted (`INSERT OR IGNORE`) or it failed.
    private func insert(_ sql: String, _ arguments: [any SQLBindable]) -> Int64? {
        locked(nil) { try connection.insert(sql, arguments) }
    }
}

private extension Show {
    init(row: Row) {
        self.init(id: row.int64(0), name: row.string(1), description: row.string(2), canonicalName: row.string(3),
                  autoErase: row.bool(4), source: row.string(5), ended: row.bool(6), categoryID: row.optionalInt64(7))
    }
}

private extension Episode {
    init(row: Row) {
        self.init(id: row.int64(0), showID: row.int64(1), name: row.string(2), season: row.int(3), episode: row.int(4),
                  aired: row.optionalString(5).flatMap { Day($0) }, description: row.optionalString(6), watched: row.bool(7),
                  position: row.double(8), filepath: row.string(9), watchedCount: row.int(10),
                  watchedAt: DjangoDateTime.date(from: row.string(11)) ?? DjangoDateTime.neverWatched)
    }
}

private extension Movie {
    init(row: Row) {
        self.init(id: row.int64(0), name: row.string(1), aired: row.string(2), watched: row.bool(3),
                  position: row.double(4), filepath: row.string(5))
    }
}

private extension SuggestedShow {
    init(row: Row) {
        self.init(id: row.int64(0), name: row.string(1), ignored: row.bool(2))
    }
}
