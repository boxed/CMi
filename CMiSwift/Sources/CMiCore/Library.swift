import Foundation

/// Sorts downloads into place and keeps the database in sync with the files on disk.
///
/// A port of the Django app's `search_for_new_files` with the TV show and movie cleanup and the
/// episode name fetching it triggers.
public actor Library {
    public let paths: Paths
    public let database: Database
    private let metadata: any MetadataProvider
    private let fileManager: FileManager
    private let customTrash: (@Sendable (URL) throws -> Void)?

    /// Downloads already dealt with by this instance. Each file is only tried once (unless a metadata lookup
    /// or the move failed), so files that aren't movies or known shows aren't looked up over and over.
    private var handledFiles: Set<String> = []
    /// Canonical names TVmaze didn't know.
    private var notTVShows: Set<String> = []
    /// Canonical names IMDb didn't know.
    private var notMovies: Set<String> = []
    private var isScanning = false

    /// - Parameter trash: Moves a file or folder to the trash. Defaults to `FileManager.trashItem`; tests can
    ///   inject something else. Files are never deleted permanently.
    public init(paths: Paths, database: Database, metadata: any MetadataProvider = LiveMetadata(),
                fileManager: FileManager = .default, trash: (@Sendable (URL) throws -> Void)? = nil) {
        self.paths = paths
        self.database = database
        self.metadata = metadata
        self.fileManager = fileManager
        self.customTrash = trash
    }

    /// Scans downloads, files new episodes/movies, creates suggested shows, trashes watched auto-erase episodes,
    /// cleans the db and empty dirs, fills in missing episode names. Returns true if the GUI should refresh,
    /// which is when an episode or movie was filed or a show was suggested.
    ///
    /// Calling this while a scan is already running returns false immediately.
    public func scan() async -> Bool {
        guard !isScanning else { return false }
        isScanning = true
        defer { isScanning = false }

        var refresh = false
        for video in findVideos(in: paths.downloads, fileManager: fileManager) where !handledFiles.contains(video) {
            do {
                switch matchFile(video) {
                case let .tvShow(path, name, number):
                    if try await handleEpisode(path: path, showName: name, number: number) {
                        refresh = true
                    }
                case let .movie(path, name, _):
                    if try await handleMovie(path: path, name: name) {
                        refresh = true
                    }
                }
                handledFiles.insert(video)
            } catch {
                logger.error("Failed to handle \(video, privacy: .public), will retry: \(String(describing: error), privacy: .public)")
            }
        }

        deleteWatchedEpisodes()
        cleanEpisodeDatabase()
        cleanEmptyDirectories()
        await fetchMissingEpisodeNames()
        cleanMovieDatabase()
        return refresh
    }

    /// "Add" on a suggested show (autoErase true = "Add (and remove watched)", false = "Add (and keep all)").
    /// Creates the show with TVmaze's summary as description and removes the suggestion. The next `scan()`
    /// files the show's episodes.
    public func addSuggestedShow(_ id: Int64, autoErase: Bool) async {
        guard let suggestion = database.suggestedShow(id) else { return }
        let description: String
        do {
            description = try await metadata.searchShows(suggestion.name).first?.overview ?? ""
        } catch {
            logger.error("Failed to fetch description of \(suggestion.name, privacy: .public): \(String(describing: error), privacy: .public)")
            description = ""
        }
        let canonicalName = canonicalFormat(suggestion.name)
        database.insertShow(name: suggestion.name, description: description, canonicalName: canonicalName, autoErase: autoErase)
        database.deleteSuggestedShow(id)

        // Let the next scan file the episodes that led to the suggestion.
        handledFiles = handledFiles.filter { path in
            guard case let .tvShow(_, name, _) = matchFile(path) else { return true }
            return canonicalFormat(name) != canonicalName
        }
    }

    // MARK: - TV shows

    /// Files the episode if its show is known. Otherwise looks the show up on TVmaze and suggests it.
    private func handleEpisode(path: String, showName: String, number: EpisodeNumber) async throws -> Bool {
        let showName = canonicalFormat(showName)
        if let show = database.show(canonicalName: showName) {
            try fileEpisode(path: path, show: show, showName: showName, number: number)
            return true
        }
        if notTVShows.contains(showName) {
            return false
        }
        let matches = try await metadata.searchShows(tvmazeName(for: showName))
        guard let match = matches.first(where: { canonicalFormat($0.name) == showName }) else {
            logger.info("Did not find \(showName, privacy: .public) on TVmaze, ignoring")
            notTVShows.insert(showName)
            return false
        }
        if database.hasSuggestedShow(named: match.name) {
            return false
        }
        database.insertSuggestedShow(name: match.name)
        logger.info("Found potential new show \(match.name, privacy: .public)")
        return true
    }

    /// Moves the file to `TV Shows/<Show>/Season N/<name> SxxEyy.ext` (or `Season <year>/<name> YYYY-MM-DD.ext`)
    /// and records it. If a file with that name is already there, the download is left where it is.
    private func fileEpisode(path: String, show: Show, showName: String, number: EpisodeNumber) throws {
        let ext = splitExtension(path).ext.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let season: Int, episode: Int, aired: Day?, fileName: String
        switch number {
        case let .seasonEpisode(s, e):
            (season, episode, aired) = (s, e, nil)
            fileName = "\(showName) S\(s.zeroPadded(2))E\(e.zeroPadded(2)).\(ext)"
        case let .aired(year, month, day):
            let day = Day(year: year, month: month, day: day)
            (season, episode, aired) = (year, 0, day)
            fileName = "\(showName) \(day).\(ext)"
        }
        let folder = paths.tvShows.appending(path: show.name, directoryHint: .isDirectory)
            .appending(path: "Season \(season)", directoryHint: .isDirectory)
        let destination = folder.appending(path: fileName, directoryHint: .notDirectory)

        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            logger.info("Move \(path, privacy: .public) -> \(destination.path(percentEncoded: false), privacy: .public)")
            try fileManager.moveItem(at: paths.downloads.appending(path: path), to: destination)
        }
        database.setEpisodeFile(show: show.id, season: season, episode: episode, aired: aired,
                                filepath: destination.path(percentEncoded: false))
    }

    /// Trashes the files of watched episodes of auto erase shows.
    private func deleteWatchedEpisodes() {
        for episode in database.watchedAutoEraseEpisodes() {
            do {
                try trash(URL(filePath: episode.filepath))
            } catch {
                // Most likely already gone. Either way the episode is done.
                logger.error("Failed to trash \(episode.filepath, privacy: .public): \(String(describing: error), privacy: .public)")
            }
            database.setEpisodeFilepath(episode.id, "")
        }
    }

    /// Forgets the files of episodes that have been removed. Skipped if the TV Shows folder is missing
    /// (e.g. an unmounted drive), so the whole library isn't forgotten.
    private func cleanEpisodeDatabase() {
        guard fileManager.fileExists(atPath: paths.tvShows.path(percentEncoded: false)) else { return }
        for episode in database.allEpisodes() where !episode.filepath.isEmpty && !fileManager.fileExists(atPath: episode.filepath) {
            database.setEpisodeFilepath(episode.id, "")
        }
    }

    /// Trashes empty season folders (and empty folders directly inside them) under `TV Shows/<Show>/`.
    /// Hidden files like .DS_Store don't count. The show folders themselves are kept.
    private func cleanEmptyDirectories() {
        for showFolder in subfolders(of: paths.tvShows) {
            for seasonFolder in subfolders(of: showFolder) {
                if isEmpty(seasonFolder) {
                    try? trash(seasonFolder)
                    continue
                }
                for folder in subfolders(of: seasonFolder) where isEmpty(folder) {
                    try? trash(folder)
                }
            }
        }
    }

    /// Fills in names and descriptions from TVmaze for episodes that have a file but no name.
    private func fetchMissingEpisodeNames() async {
        var seriesCache: [String: SeriesEpisodes?] = [:]
        for episode in database.episodesMissingName() {
            guard let show = database.show(episode.showID) else { continue }
            let key = show.name.lowercased()
            if seriesCache[key] == nil {
                do {
                    seriesCache[key] = try await seriesEpisodes(named: key)
                } catch {
                    logger.error("Failed to fetch episodes of \(show.name, privacy: .public): \(String(describing: error), privacy: .public)")
                    seriesCache[key] = .some(nil)
                }
            }
            guard let series = seriesCache[key] ?? nil else { continue }
            let info = episode.episode != 0
                ? series.bySeasonEpisode[SeasonEpisode(season: episode.season, episode: episode.episode)]
                : episode.aired.flatMap { series.byAirdate[$0] }
            if let info {
                database.setEpisodeInfo(episode.id, name: info.name, description: info.overview)
            }
        }
    }

    private struct SeasonEpisode: Hashable {
        var season: Int
        var episode: Int
    }

    private struct SeriesEpisodes {
        var bySeasonEpisode: [SeasonEpisode: EpisodeInfo] = [:]
        var byAirdate: [Day: EpisodeInfo] = [:]
    }

    /// The episodes of the best TVmaze match, or nil if there is none.
    private func seriesEpisodes(named name: String) async throws -> SeriesEpisodes? {
        guard let match = try await metadata.searchShows(tvmazeName(for: name)).first else { return nil }
        var result = SeriesEpisodes()
        for info in try await metadata.episodes(ofShow: match.id) {
            if let season = info.season, let number = info.number {
                result.bySeasonEpisode[SeasonEpisode(season: season, episode: number)] = info
            }
            if let airdate = info.airdate {
                result.byAirdate[airdate] = info
            }
        }
        return result
    }

    // MARK: - Movies

    /// Files the download in `Movies/` if IMDb knows the title.
    private func handleMovie(path: String, name: String) async throws -> Bool {
        guard let title = try await imdbTitle(for: cleanMovieName(name)) else { return false }
        let fileName = String(path.split(separator: "/").last ?? Substring(path))
        let destination = paths.movies.appending(path: fileName, directoryHint: .notDirectory)
        try fileManager.createDirectory(at: paths.movies, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else {
            logger.error("Not moving \(path, privacy: .public): \(destination.path(percentEncoded: false), privacy: .public) already exists")
            return false
        }
        logger.info("Move \(path, privacy: .public) -> \(destination.path(percentEncoded: false), privacy: .public)")
        try fileManager.moveItem(at: paths.downloads.appending(path: path), to: destination)
        database.insertMovie(name: title.title, aired: title.year.map(String.init) ?? "", filepath: destination.path(percentEncoded: false))
        return true
    }

    /// The IMDb title whose canonical form equals the name. If there is none, the last word of the name is
    /// dropped and IMDb is asked again (it's often junk like a release group).
    private func imdbTitle(for name: String) async throws -> TitleInfo? {
        if name == "movies" || name == "tv shows" {
            return nil
        }
        let name = canonicalFormat(name)
        if name.isEmpty || notMovies.contains(name) {
            return nil
        }
        if let title = try await bestTitle(name) {
            return title
        }
        let shorter = canonicalFormat(name.lastIndex(of: " ").map { String(name[..<$0]) } ?? name)
        if !shorter.isEmpty, shorter != name, let title = try await bestTitle(shorter) {
            return title
        }
        logger.info("\(name, privacy: .public) was not found on IMDb")
        notMovies.insert(name)
        return nil
    }

    /// The best (first) search result whose canonical title is exactly `name`.
    private func bestTitle(_ name: String) async throws -> TitleInfo? {
        try await metadata.searchTitles(name).first { canonicalFormat($0.title) == name }
    }

    /// Forgets movies whose file is gone. Skipped if the Movies folder is missing.
    private func cleanMovieDatabase() {
        guard fileManager.fileExists(atPath: paths.movies.path(percentEncoded: false)) else { return }
        for movie in database.allMovies() where !fileManager.fileExists(atPath: movie.filepath) {
            database.deleteMovie(movie.id)
        }
    }

    // MARK: - Files

    private func trash(_ url: URL) throws {
        if let customTrash {
            try customTrash(url)
        } else {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
        }
    }

    private func subfolders(of url: URL) -> [URL] {
        let names = (try? fileManager.contentsOfDirectory(atPath: url.path(percentEncoded: false))) ?? []
        return names.sorted().map { url.appending(path: $0, directoryHint: .isDirectory) }.filter { folder in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    /// No subfolders (hidden or not) and no visible files.
    private func isEmpty(_ folder: URL) -> Bool {
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else { return false }
        return names.allSatisfy { name in
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: folder.appending(path: name).path(percentEncoded: false), isDirectory: &isDirectory)
            return name.hasPrefix(".") && !(exists && isDirectory.boolValue)
        }
    }
}

/// Names that TVmaze knows by another name (Swedish titles of kids' shows).
func tvmazeName(for showName: String) -> String {
    [
        "hej jycke": "hey duggee",
        "stadens hjältar": "heroes of the city",
    ][showName] ?? showName
}
