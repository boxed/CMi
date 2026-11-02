import Foundation
@testable import CMiCore

/// A fresh, empty folder under the package's (gitignored) `scratch/` folder. Never the system temp dir.
func makeScratchFolder(_ name: String = #function) throws -> URL {
    let packageRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let safeName = name.filter { $0.isLetter || $0.isNumber }
    let folder = packageRoot.appending(path: "scratch/CMiCoreTests/\(safeName)-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// Creates a sparse file of `size` bytes (big enough to look like a real video without using disk).
func makeVideo(_ url: URL, size: UInt64 = UInt64(minimumFileSize)) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    #expect(FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil))
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: size)
    try handle.close()
}

func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
}

import Testing

/// Canned TVmaze/IMDb answers. Records the queries it got.
final class StubMetadata: MetadataProvider, @unchecked Sendable {
    var shows: [String: [ShowInfo]] = [:]
    var episodes: [Int: [EpisodeInfo]] = [:]
    var titles: [String: [TitleInfo]] = [:]
    var failing = false
    private let lock = NSLock()
    private var _queries: [String] = []

    var queries: [String] { lock.withLock { _queries } }

    private func record(_ query: String) throws {
        lock.withLock { _queries.append(query) }
        if failing { throw URLError(.notConnectedToInternet) }
    }

    func searchShows(_ name: String) async throws -> [ShowInfo] {
        try record("show:\(name)")
        return shows[name] ?? []
    }

    func episodes(ofShow id: Int) async throws -> [EpisodeInfo] {
        try record("episodes:\(id)")
        return episodes[id] ?? []
    }

    func searchTitles(_ title: String) async throws -> [TitleInfo] {
        try record("title:\(title)")
        return titles[title] ?? []
    }
}

/// Records what would have been trashed, and actually removes it from the scratch folder.
final class TrashRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _trashed: [String] = []
    var trashed: [String] { lock.withLock { _trashed } }

    var trash: @Sendable (URL) throws -> Void {
        { [self] url in
            lock.withLock { _trashed.append(url.path(percentEncoded: false)) }
            try FileManager.default.removeItem(at: url)
        }
    }
}
