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
    /// Downloads come with whatever subtitles happen to be in the file, so they're turned off. Streams like
    /// SVT Play mark the ones to show (Swedish for foreign language programs), so those are kept.
    var keepsSubtitles = false
}
