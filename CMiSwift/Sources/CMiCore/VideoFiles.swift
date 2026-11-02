import Foundation

/// Folder names (case insensitive) that are never scanned: where CMi files things away, and
/// where downloads in progress and sample clips live.
private let skippedFolderNames: Set<String> = ["movies", "tv shows", "incomplete", "sample"]

/// All video files under `downloads`, as NFC normalized paths relative to it, sorted.
/// Hidden files and the `skippedFolderNames` folders are skipped.
public func findVideos(in downloads: URL, fileManager: FileManager = .default) -> [String] {
    var videos: [String] = []

    func walk(_ relativeDirectory: String) {
        let directory = relativeDirectory.isEmpty ? downloads : downloads.appending(path: relativeDirectory)
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) else { return }
        for name in names.sorted() where !name.hasPrefix(".") {
            let relativePath = relativeDirectory.isEmpty ? name : relativeDirectory + "/" + name
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.appending(path: name).path(percentEncoded: false), isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                if !skippedFolderNames.contains(name.lowercased()) {
                    walk(relativePath)
                }
            } else if hasSupportedExtension(name) {
                videos.append(relativePath.precomposedStringWithCanonicalMapping)
            }
        }
    }

    walk("")
    return videos
}

/// What to actually play for a path: the path itself for a file. For a directory, the first video
/// in it (recursively) that isn't a sample and is at least `minimumFileSize`, or the directory if there is none.
public func playablePath(_ path: String, fileManager: FileManager = .default) -> String {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue,
          let enumerator = fileManager.enumerator(at: URL(filePath: path, directoryHint: .isDirectory),
                                                  includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
        return path
    }
    for case let url as URL in enumerator {
        let name = url.lastPathComponent
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { continue }
        if values.isRegularFile != true {
            if name.lowercased().contains("sample") {
                enumerator.skipDescendants()
            }
            continue
        }
        if !name.lowercased().contains("sample"), (values.fileSize ?? 0) >= minimumFileSize,
           supportedFileFormats.contains(splitExtension(name).ext.lowercased()) {
            return url.path(percentEncoded: false)
        }
    }
    return path
}
