import AppKit
import VLCKit

/// Plays a `Playable` with VLCKit and reports progress back. Times are in milliseconds, like VLCTime.
@MainActor
final class Player: NSObject {
    let videoView: VLCVideoView
    private let mediaPlayer: VLCMediaPlayer

    private(set) var playable: Playable?
    private(set) var isPaused = false
    private var hasReportedEnd = false
    private var hasFixedTracks = false
    /// Whether the subtitles to start with have been chosen (or the viewer has picked some).
    private var hasPickedSubtitles = false
    private var progressTimer: Timer?
    /// For estimating how far ahead is downloaded: a time in the video, and VLC's count of bytes read then.
    private var bufferAnchor = (milliseconds: 0, readBytes: Int32(0))
    private var byteSize: Int?

    /// Called after playback stops, for whatever reason.
    var onStop: (() -> Void)?
    /// Called when anything the overlay shows changes (pause state, volume).
    var onChange: (() -> Void)?
    /// Called when playback continues after a pause, however that happened (controls, keys, media keys).
    var onResume: (() -> Void)?

    /// Jump size for skipping intros and commercials.
    static let jumpSeconds: Int32 = 30

    /// How much VLC buffers, in milliseconds. Its default of about a second stutters over Wi-Fi and network
    /// shares. Adjustable with e.g. `defaults write net.kodare.CMi networkCaching -int 15000`.
    static var networkCaching: Int { UserDefaults.standard.object(forKey: "networkCaching") as? Int ?? 8000 }
    static var fileCaching: Int { UserDefaults.standard.object(forKey: "fileCaching") as? Int ?? 3000 }
    /// How far ahead VLC may download, in megabytes, when the network is faster than the video. Caching above is
    /// a fixed delay; this is what lets a good connection build up minutes of buffer. VLC's default is 16 MB.
    static var readAheadMegabytes: Int { UserDefaults.standard.object(forKey: "readAheadMegabytes") as? Int ?? 256 }

    override init() {
        videoView = VLCVideoView(frame: .zero)
        videoView.autoresizingMask = [.width, .height]
        videoView.fillScreen = false
        mediaPlayer = VLCMediaPlayer(videoView: videoView)
        super.init()
        mediaPlayer.delegate = self
    }

    var isPlaying: Bool { playable != nil }

    func play(_ playable: Playable) {
        stop(report: true)
        self.playable = playable
        hasReportedEnd = false
        hasFixedTracks = false
        hasPickedSubtitles = false
        isPaused = false
        byteSize = playable.byteSize ?? (playable.url.isFileURL ? Self.fileSize(playable.url) : nil)
        bufferAnchor = (playable.startMilliseconds, 0)
        let media = VLCMedia(url: playable.url)
        media.addOptions(["network-caching": Self.networkCaching, "file-caching": Self.fileCaching,
                          "prefetch-buffer-size": Self.readAheadMegabytes * 1024])   // in KiB
        mediaPlayer.media = media
        mediaPlayer.play()
        let remembered = playable.subtitlesKey.flatMap { Self.rememberedSubtitles[$0] }
        for file in playable.subtitleFiles {
            mediaPlayer.addPlaybackSlave(file, type: .subtitle, enforce: remembered == nil && playable.defaultSubtitles == .file(file))
        }
        mediaPlayer.audio?.volume = Int32(volume * 100)
        if playable.startMilliseconds > 0 {
            mediaPlayer.time = VLCTime(int: Int32(playable.startMilliseconds))   // not seek(to:): the duration isn't known yet
        }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reportProgress() }
        }
        onChange?()
    }

    func stop() {
        stop(report: true)
    }

    private func stop(report: Bool) {
        guard let playable else { return }
        progressTimer?.invalidate()
        progressTimer = nil
        if report && !hasReportedEnd && currentTime > 0 {
            let position = currentTime
            Task { await playable.reportPosition(position) }
        }
        self.playable = nil
        mediaPlayer.stop()
        isPaused = false
        onStop?()
    }

    // MARK: Controls

    var currentTime: Int { Int(mediaPlayer.time.intValue) }
    var duration: Int { Int(mediaPlayer.media?.length.intValue ?? 0) }

    func playPause() {
        guard isPlaying else { return }
        if isPaused { mediaPlayer.play() } else { mediaPlayer.pause() }
        isPaused.toggle()
        onChange?()
        if !isPaused { onResume?() }
    }

    func jumpForward() { seek(to: currentTime + Int(Self.jumpSeconds) * 1000) }
    func jumpBackward() { seek(to: currentTime - Int(Self.jumpSeconds) * 1000) }
    func toBeginning() { seek(to: 0) }

    func seek(to milliseconds: Int) {
        let target = min(max(0, milliseconds), duration)
        // VLC keeps what it has read ahead when jumping into it; anywhere else it starts reading from there.
        if !(currentTime...max(currentTime, bufferedUntil ?? 0)).contains(target) {
            bufferAnchor = (target, mediaPlayer.media?.statistics.readBytes ?? 0)
        }
        mediaPlayer.time = VLCTime(int: Int32(target))
    }

    /// Pauses just before the end, so the viewer can decide whether it's done.
    func toEnd() {
        if !isPaused { playPause() }
        seek(to: duration - 1000)
    }

    /// How far into the video is downloaded, estimated from the bytes VLC has read since the last seek and the
    /// file's average bitrate. Nil when the file's size is unknown (streams).
    var bufferedUntil: Int? {
        guard let byteSize, byteSize > 0, duration > 0, let read = mediaPlayer.media?.statistics.readBytes else { return nil }
        // VLC counts in 32 bits, so this wraps every 4 GB
        let bytes = Double(UInt32(bitPattern: read &- bufferAnchor.readBytes))
        let milliseconds = bufferAnchor.milliseconds + Int(bytes / Double(byteSize) * Double(duration))
        return min(duration, max(currentTime, milliseconds))
    }

    private static func fileSize(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }

    /// Writes the current video frame as a PNG (VLC renders it, so this checks decoding works).
    func saveVideoFrame(to url: URL) {
        mediaPlayer.saveVideoSnapshot(at: url.path, withWidth: 0, andHeight: 0)
    }

    // MARK: Subtitles

    /// The name VLC gives the subtitles showing, e.g. "Track 2 - [English]". Nil when they're off.
    var subtitlesName: String? {
        let current = mediaPlayer.currentVideoSubTitleIndex
        guard current >= 0, let i = subtitleTracks.indexes.firstIndex(of: current) else { return nil }
        return subtitleTracks.names[i]
    }

    var hasSubtitles: Bool { !subtitleTracks.indexes.isEmpty }

    /// The subtitle tracks, without VLC's "Disable" entry.
    private var subtitleTracks: (names: [String], indexes: [Int32]) {
        let names = mediaPlayer.videoSubTitlesNames.map { $0 as? String ?? "" }
        let indexes = mediaPlayer.videoSubTitlesIndexes.map { ($0 as? NSNumber)?.int32Value ?? -1 }
        let tracks = zip(names, indexes).filter { $0.1 >= 0 }
        return (tracks.map(\.0), tracks.map(\.1))
    }

    /// Shows the next subtitles, or none after the last ones. Remembered for the show or movie.
    func nextSubtitles() {
        guard isPlaying else { return }
        let indexes = [-1] + subtitleTracks.indexes
        let current = indexes.firstIndex(of: mediaPlayer.currentVideoSubTitleIndex) ?? 0
        mediaPlayer.currentVideoSubTitleIndex = indexes[(current + 1) % indexes.count]
        hasPickedSubtitles = true
        if let key = playable?.subtitlesKey {
            Self.rememberedSubtitles[key] = subtitlesName ?? ""
        }
        onChange?()
    }

    /// The track name picked last for each `Playable.subtitlesKey`, "" for none.
    private static var rememberedSubtitles: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "subtitles") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "subtitles") }
    }

    /// Starts the subtitles picked last time for this show or movie, or else the playable's default. Subtitles
    /// from files turn up a moment after the video starts, so this keeps looking for a few seconds.
    private func pickSubtitles() {
        guard let playable else { return }
        let tracks = subtitleTracks
        let isLate = currentTime - playable.startMilliseconds > 8000
        func select(_ i: Int?) {
            mediaPlayer.currentVideoSubTitleIndex = i.map { tracks.indexes[$0] } ?? -1
            hasPickedSubtitles = true
        }
        if let remembered = playable.subtitlesKey.flatMap({ Self.rememberedSubtitles[$0] }) {
            if remembered.isEmpty {
                select(nil)
            } else if let i = tracks.names.firstIndex(of: remembered) {
                select(i)
            } else if isLate {
                select(tracks.names.isEmpty ? nil : 0)   // another file of the same show, with other track names
            }
            return
        }
        switch playable.defaultSubtitles {
        case .off:
            select(nil)
        case .file:
            hasPickedSubtitles = true   // VLC shows it once it has loaded it
        case .named(let name):
            if let i = tracks.names.firstIndex(where: { Self.trackName($0, isNamed: name) }) {
                select(i)
            } else if isLate {
                select(nil)
            }
        case .language(let language):
            if let i = tracks.names.firstIndex(where: { $0.localizedCaseInsensitiveContains(language) }) {
                select(i)
            } else if isLate {
                select(nil)
            }
        }
    }

    /// Whether VLC's name for a track is "<group> <name> - [<language>]" or "<name>".
    private static func trackName(_ trackName: String, isNamed name: String) -> Bool {
        let trimmed = trackName.replacing(/\ - \[[^\]]*\]$/, with: "")
        return trimmed == name || trimmed.hasSuffix(" " + name)
    }

    // MARK: Volume

    /// 0...1, remembered between launches.
    var volume: Float {
        get { UserDefaults.standard.object(forKey: "volume") as? Float ?? 1 }
        set {
            let v = min(1, max(0, newValue))
            UserDefaults.standard.set(v, forKey: "volume")
            mediaPlayer.audio?.volume = Int32(v * 100)
            onChange?()
        }
    }

    func raiseVolume() { volume += 0.1 }
    func lowerVolume() { volume -= 0.1 }

    // MARK: Progress

    /// Every 5 seconds: report the position, or that the end was reached (the last 5%), and stop
    /// at the very end. Same rules as the old player.
    private func reportProgress() {
        guard let playable, !isPaused else { return }
        let current = currentTime, end = duration
        guard end > 2 else { return }   // length not known yet
        if Double(abs(end - current)) / Double(end) < 0.05 {
            if !hasReportedEnd {
                hasReportedEnd = true
                Task { await playable.reportEnded() }
            }
            if end - current < 3000 { stop(report: false) }
        } else {
            Task { await playable.reportPosition(current) }
        }
    }

    /// Prefer an English audio track.
    private func fixTracks() {
        hasFixedTracks = true
        let names = mediaPlayer.audioTrackNames.compactMap { $0 as? String }
        let indexes = mediaPlayer.audioTrackIndexes.compactMap { ($0 as? NSNumber)?.int32Value }
        if let i = names.firstIndex(where: { $0.localizedCaseInsensitiveContains("english") }), i < indexes.count {
            mediaPlayer.currentAudioTrackIndex = indexes[i]
        }
    }
}

extension Player: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor in
            if isPlaying && !hasFixedTracks { fixTracks() }
            if isPlaying && !hasPickedSubtitles { pickSubtitles() }
        }
    }

    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in
            guard isPlaying else { return }
            switch mediaPlayer.state {
            case .ended:
                if !hasReportedEnd, let playable {
                    hasReportedEnd = true
                    Task { await playable.reportEnded() }
                }
                stop(report: false)
            case .error:
                stop(report: true)
            default:
                break
            }
        }
    }
}
