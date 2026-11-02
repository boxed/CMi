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
    private var progressTimer: Timer?

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
        isPaused = false
        let media = VLCMedia(url: playable.url)
        media.addOptions(["network-caching": Self.networkCaching, "file-caching": Self.fileCaching,
                          "prefetch-buffer-size": Self.readAheadMegabytes * 1024])   // in KiB
        mediaPlayer.media = media
        mediaPlayer.play()
        mediaPlayer.audio?.volume = Int32(volume * 100)
        if playable.startMilliseconds > 0 {
            mediaPlayer.time = VLCTime(int: Int32(playable.startMilliseconds))
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

    func jumpForward() { mediaPlayer.jumpForward(Self.jumpSeconds) }
    func jumpBackward() { mediaPlayer.jumpBackward(Self.jumpSeconds) }
    func toBeginning() { mediaPlayer.time = VLCTime(int: 0) }
    func seek(to milliseconds: Int) { mediaPlayer.time = VLCTime(int: Int32(min(max(0, milliseconds), duration))) }

    /// Pauses just before the end, so the viewer can decide whether it's done.
    func toEnd() {
        if !isPaused { playPause() }
        mediaPlayer.time = VLCTime(int: Int32(max(0, duration - 1000)))
    }

    /// Writes the current video frame as a PNG (VLC renders it, so this checks decoding works).
    func saveVideoFrame(to url: URL) {
        mediaPlayer.saveVideoSnapshot(at: url.path, withWidth: 0, andHeight: 0)
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

    /// Subtitles off (unless the playable keeps them), and prefer an English audio track.
    private func fixTracks() {
        hasFixedTracks = true
        if playable?.keepsSubtitles != true {
            mediaPlayer.currentVideoSubTitleIndex = -1
        }
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
