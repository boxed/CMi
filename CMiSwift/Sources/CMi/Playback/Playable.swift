import Foundation

/// Something to play, and where to report how far the viewer got. Times are in milliseconds.
struct Playable {
    var title: String
    var url: URL
    var startMilliseconds: Int
    /// Called every few seconds during playback.
    var reportPosition: @MainActor (_ milliseconds: Int) async -> Void
    /// Called once when the viewer reaches the end (the last 5%).
    var reportEnded: @MainActor () async -> Void
    /// Subtitle files to load along with the video: Plex's that aren't in the video file. VLC finds the ones
    /// next to local files by itself.
    var subtitleFiles: [URL] = []
    /// What to show until the viewer picks something for `subtitlesKey`.
    var defaultSubtitles = DefaultSubtitles.off
    /// The subtitles the viewer picks are remembered under this (a show or a movie), for next time.
    var subtitlesKey: String?
    /// The file's size in bytes, to show how much is buffered. Unknown for streams like SVT Play's.
    var byteSize: Int?
}

enum DefaultSubtitles: Equatable {
    /// Downloads come with whatever subtitles happen to be in the file, so they're off unless asked for.
    case off
    /// The track with this name in the stream: VLC calls SVT Play's "Svenska" "text Svenska - [Swedish]".
    /// SVT marks one to show by default, but VLC doesn't show it.
    case named(String)
    /// The ones loaded from this one of `subtitleFiles` (Plex's choice, from the account's subtitle settings).
    case file(URL)
    /// The first track whose name mentions this language, e.g. "English" (Plex, for ones in the video file).
    case language(String)
}
