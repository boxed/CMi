import Foundation

/// Keeps the next episodes of the show being watched on disk, so a bad connection can't stop one halfway, and
/// a couple can be watched without one. Follows the episode played last: the `ahead` unwatched episodes after it
/// are downloaded, it's kept until it's watched if it was downloaded, and everything else is deleted.
///
/// `folder/<ratingKey>/` has the video, its subtitles and `episode.json`, which is written last, so a folder
/// without it is an unfinished download. `folder/state.json` has the episode played last, and episodes watched
/// while the server couldn't be reached, to tell it later.
public actor PlexDownloads {
    let plex: Plex
    public let folder: URL
    let ahead: Int

    private var syncing: Task<Void, Never>?
    private var needsSync = false
    /// What interrupted downloads got, by ratingKey, to continue from there.
    private var resumeData: [String: Data] = [:]

    public init(plex: Plex, folder: URL, ahead: Int = 2) {
        self.plex = plex
        self.folder = folder
        self.ahead = ahead
    }

    /// Call when an episode starts playing: its show is the one to keep downloaded. Returns when the downloads
    /// are done, so call it in a task of its own.
    public func played(_ ratingKey: String, showID: String) async {
        var state = loadState()
        state.showID = showID
        state.episodeID = ratingKey
        saveState(state)
        await sync()
    }

    /// Marks as watched, or remembers to when the server can't be reached. Then downloads the next episode,
    /// in the background.
    public func markWatched(_ ratingKey: String) async {
        if await !plex.scrobble(ratingKey) {
            var state = loadState()
            if !state.unreportedWatched.contains(ratingKey) { state.unreportedWatched.append(ratingKey) }
            saveState(state)
        }
        Task { await sync() }
    }

    /// The downloaded episodes not watched yet, in episode order.
    public func downloads() -> [PlexDownload] {
        let watched = loadState().unreportedWatched
        return folderNames().filter { !watched.contains($0) }.compactMap(download(of:)).sorted {
            ($0.episode.season, $0.episode.index ?? .max) < ($1.episode.season, $1.episode.index ?? .max)
        }
    }

    public func download(of ratingKey: String) -> PlexDownload? {
        let entry = folder.appending(path: ratingKey, directoryHint: .isDirectory)
        guard let data = try? Data(contentsOf: entry.appending(path: "episode.json")),
              let info = try? JSONDecoder().decode(Info.self, from: data)
        else { return nil }
        let file = { (name: String) in entry.appending(path: name, directoryHint: .notDirectory) }
        return PlexDownload(episode: info.episode, showID: info.showID, video: file(info.video),
                            subtitles: info.subtitles.map(file), selectedSubtitles: info.selectedSubtitles.map(file),
                            selectedLanguage: info.selectedLanguage)
    }

    /// Reports what was watched offline, deletes what's no longer needed and downloads what's missing. Call now and
    /// then, so interrupted downloads continue. Calls while one runs make it start over once it's done.
    public func sync() async {
        if let syncing {
            needsSync = true
            return await syncing.value
        }
        let task = Task {
            repeat {
                needsSync = false
                await syncOnce()
            } while needsSync
            syncing = nil
        }
        syncing = task
        await task.value
    }

    private func syncOnce() async {
        // First, so the server knows what's next
        for id in loadState().unreportedWatched where await plex.scrobble(id) {
            var state = loadState()
            state.unreportedWatched.removeAll { $0 == id }
            saveState(state)
        }
        let state = loadState()
        guard state.unreportedWatched.isEmpty, let showID = state.showID,
              let episodes = try? await plex.episodes(ofShow: showID)
        else { return }   // can't reach the server, keep everything for now
        let wanted = Self.episodes(episodes, after: state.episodeID, count: ahead)
        let current = episodes.first { $0.id == state.episodeID && !$0.watched }
        let keep = Set((wanted + [current].compactMap { $0 }).map(\.id))
        for id in folderNames() where !keep.contains(id) {
            try? FileManager.default.removeItem(at: folder.appending(path: id, directoryHint: .isDirectory))
        }
        for episode in wanted where download(of: episode.id) == nil {
            guard !needsSync else { return }   // what to keep may have changed while downloading
            do {
                try await download(episode, showID: showID)
            } catch {
                return   // try again on the next sync
            }
        }
    }

    /// The first `count` unwatched episodes after the one with the ratingKey `id`, or from the beginning.
    static func episodes(_ episodes: [PlexEpisode], after id: String?, count: Int) -> [PlexEpisode] {
        let start = episodes.firstIndex { $0.id == id }.map { $0 + 1 } ?? 0
        return Array(episodes[start...].filter { !$0.watched }.prefix(count))
    }

    private func download(_ episode: PlexEpisode, showID: String) async throws {
        let playback = try await plex.playback(of: episode.id)
        let entry = folder.appending(path: episode.id, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: entry)
        try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)

        let request = try await plex.request(playback.streamURL, timeout: 30)
        let (temporary, response): (URL, URLResponse)
        do {
            if let data = resumeData[episode.id] {
                (temporary, response) = try await plex.session.download(resumeFrom: data)
            } else {
                (temporary, response) = try await plex.session.download(for: request)
            }
        } catch {
            resumeData[episode.id] = (error as? URLError)?.downloadTaskResumeData
            throw error
        }
        resumeData[episode.id] = nil
        defer { try? FileManager.default.removeItem(at: temporary) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw PlexError.httpStatus(status) }
        let video = "video." + (playback.streamURL.pathExtension.isEmpty ? "mkv" : playback.streamURL.pathExtension)
        try FileManager.default.moveItem(at: temporary, to: entry.appending(path: video, directoryHint: .notDirectory))

        var info = Info(episode: episode, showID: showID, video: video)
        for subtitle in playback.subtitles {
            if subtitle.isDownloadable, let file = try? await plex.download(subtitle, to: entry) {
                info.subtitles.append(file.lastPathComponent)
                if subtitle.selected { info.selectedSubtitles = file.lastPathComponent }
            } else if subtitle.selected && subtitle.fileURL == nil {
                info.selectedLanguage = subtitle.language
            }
        }
        try JSONEncoder().encode(info).write(to: entry.appending(path: "episode.json"), options: .atomic)
    }

    // MARK: Files

    private struct Info: Codable {
        var episode: PlexEpisode
        var showID: String
        /// File names in the episode's folder.
        var video: String
        var subtitles: [String] = []
        var selectedSubtitles: String?
        var selectedLanguage: String?
    }

    private struct State: Codable {
        var showID: String?
        var episodeID: String?
        var unreportedWatched: [String] = []
    }

    private var stateFile: URL { folder.appending(path: "state.json", directoryHint: .notDirectory) }

    private func loadState() -> State {
        (try? Data(contentsOf: stateFile)).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    private func saveState(_ state: State) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(state).write(to: stateFile, options: .atomic)
    }

    private func folderNames() -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.map(\.lastPathComponent)
    }
}

/// A downloaded episode.
public struct PlexDownload: Sendable {
    /// As it was when downloaded.
    public var episode: PlexEpisode
    public var showID: String
    public var video: URL
    public var subtitles: [URL]
    /// One of `subtitles`, if those were chosen in Plex.
    public var selectedSubtitles: URL?
    /// The language of subtitles in the video file chosen in Plex.
    public var selectedLanguage: String?
}
