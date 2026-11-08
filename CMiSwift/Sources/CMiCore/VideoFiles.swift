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

/// Extensions (with the dot) of subtitle files VLC shows.
public let subtitleExtensions: Set<String> = [".srt", ".ass", ".ssa", ".sub", ".idx", ".vtt", ".smi"]

/// Subtitle files next to the video named after it ("Video.srt", "Video.en.srt"), as the part of their
/// name after the video's ("", ".en") and their extension.
func subtitlesNextTo(_ video: URL, fileManager: FileManager = .default) -> [(source: URL, suffix: String)] {
    let folder = video.deletingLastPathComponent()
    let videoName = splitExtension(video.lastPathComponent).name
    let names = (try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
    return names.sorted().compactMap { name in
        let (base, ext) = splitExtension(name)
        guard subtitleExtensions.contains(ext.lowercased()), base.hasPrefix(videoName) else { return nil }
        let rest = base.dropFirst(videoName.count)
        guard rest.isEmpty || rest.hasPrefix(".") else { return nil }
        return (folder.appending(path: name, directoryHint: .notDirectory), rest + ext)
    }
}

/// The subtitles that belong to a downloaded video, with the names to give them when the video is renamed to
/// `newName` (without extension) so VLC still finds them: "Video.en.srt" becomes "<newName>.en.srt".
/// Releases often put them in a "Subs" folder instead: "Subs/Video.srt", "Subs/<video name>/2_English.srt" for a
/// season in one folder, or just "Subs/2_English.srt". The last two become "<newName>.2_English.srt" (VLC finds
/// subtitles whose name contains the video's). Files in "Subs" not named after the video are only taken when the video
/// is alone in its folder and there are no folders in "Subs", since then they can't be another video's.
func subtitles(of video: URL, renamedTo newName: String, fileManager: FileManager = .default) -> [(source: URL, name: String)] {
    var result = subtitlesNextTo(video, fileManager: fileManager).map { ($0.source, newName + $0.suffix) }

    func contents(of folder: URL) -> [String] {
        ((try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }
    func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) && isDirectory.boolValue
    }
    func subtitleFiles(in folder: URL) -> [URL] {
        contents(of: folder).filter { subtitleExtensions.contains(splitExtension($0).ext.lowercased()) }
            .map { folder.appending(path: $0, directoryHint: .notDirectory) }
    }

    let folder = video.deletingLastPathComponent()
    let videoName = splitExtension(video.lastPathComponent).name
    let siblings = contents(of: folder)
    for subsName in siblings where ["subs", "subtitles"].contains(subsName.lowercased()) {
        let subs = folder.appending(path: subsName, directoryHint: .isDirectory)
        let own = subs.appending(path: videoName, directoryHint: .isDirectory)
        let named = subtitlesNextTo(subs.appending(path: video.lastPathComponent), fileManager: fileManager)
        if isFolder(own) {
            result += subtitleFiles(in: own).map { ($0, newName + "." + $0.lastPathComponent) }
        } else if !named.isEmpty {
            result += named.map { ($0.source, newName + $0.suffix) }
        } else if siblings.filter(hasSupportedExtension).count == 1,
                  !contents(of: subs).contains(where: { isFolder(subs.appending(path: $0)) }) {
            result += subtitleFiles(in: subs).map { ($0, newName + "." + $0.lastPathComponent) }
        }
    }
    return result
}
