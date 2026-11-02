import Foundation

/// Where CMi keeps its database and where it looks for (and files away) downloaded videos.
public struct Paths: Sendable {
    /// Holds `cmi.db`. Shared with the old Django app.
    public var supportFolder: URL
    /// Scanned for new videos. Episodes and movies are filed into subfolders of it.
    public var downloads: URL

    /// `downloads/TV Shows`: episodes are moved to `TV Shows/<Show>/Season N/`.
    public var tvShows: URL { downloads.appending(path: "TV Shows", directoryHint: .isDirectory) }
    /// `downloads/Movies`.
    public var movies: URL { downloads.appending(path: "Movies", directoryHint: .isDirectory) }
    /// `supportFolder/cmi.db`.
    public var database: URL { supportFolder.appending(path: "cmi.db", directoryHint: .notDirectory) }

    public init(supportFolder: URL, downloads: URL) {
        self.supportFolder = supportFolder
        self.downloads = downloads
    }

    /// `~/Library/Application Support/CMi/` (or `$CMI_SUPPORT_FOLDER`, like the Django app) and `~/Downloads`.
    public static var standard: Paths {
        let environment = ProcessInfo.processInfo.environment
        let home = environment["HOME"].map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let supportFolder = environment["CMI_SUPPORT_FOLDER"].map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? home.appending(path: "Library/Application Support/CMi", directoryHint: .isDirectory)
        return Paths(supportFolder: supportFolder, downloads: home.appending(path: "Downloads", directoryHint: .isDirectory))
    }
}
