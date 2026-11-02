import Foundation

// Guessing what a downloaded file is from its name. A port of CMi/engine.py; the regexes are the same
// (Python's `(?P<name>…)` spelled `(?<name>…)` for ICU) and are matched the same way as Python's `re.match`:
// anchored at the start, not at the end.

/// How an episode is identified: by season and episode, or (talk shows, news) by the day it aired.
public enum EpisodeNumber: Sendable, Hashable {
    case seasonEpisode(season: Int, episode: Int)
    case aired(year: Int, month: Int, day: Int)
}

/// What `matchFile` thinks a file is. `path` is always the path that was passed in.
public enum MediaMatch: Sendable, Hashable {
    case tvShow(path: String, name: String, number: EpisodeNumber)
    /// `year` is 0 if the name didn't contain one.
    case movie(path: String, name: String, year: Int)
}

/// Video file extensions CMi picks up (compared case insensitively).
public let supportedFileFormats: Set<String> = [".avi", ".mkv", ".m4v", ".mov", ".mp4"]

/// Files in a downloaded directory smaller than this are not considered the video (they're samples etc.).
public let minimumFileSize = 1024 * 1024 * 50

/// Normalizes a show or movie name for comparison: lowercased, punctuation and release junk
/// (`[group]` prefixes, `www.site.com`, `720p`, …) turned into single spaces, `&` spelled "and",
/// plus a few hand made aliases.
public func canonicalFormat(_ s: String) -> String {
    var result = s.lowercased()
    result = Patterns.canonicalRemove.replacingMatches(in: result, with: "")
    result = Patterns.canonicalSpace.replacingMatches(in: result, with: " ")
    result = result.replacingOccurrences(of: "&", with: "and")
    result = Patterns.spaces.replacingMatches(in: result, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    return canonicalAliases[result] ?? result
}

private let canonicalAliases = [
    "the daily show with jon stewart": "the daily show",
    "marvels agents of s h i e l d": "marvels agents of shield",
    "cosmos a spacetime odyssey": "cosmos a space time odyssey",
    "stargate sg1": "stargate sg-1",
    "stargate sg 1": "stargate sg-1",
]

/// Classifies a path (relative to the downloads folder) as a TV show episode or a movie.
///
/// If the path has directories, the file name alone is tried first, then the whole path
/// (so `Black Books/Series 2/EP3 - The Fixer.avi` works). Anything unrecognizable is a movie.
public func matchFile(_ path: String) -> MediaMatch {
    if path.contains("/"), let fileName = path.split(separator: "/", omittingEmptySubsequences: false).last {
        let fileName = String(fileName)
        if let match = matchVideo(path: path, video: canonicalFormat(splitExtension(fileName).name)) {
            return match
        }
    }
    return matchVideo(path: path, video: canonicalFormat(splitExtension(path).name))
        ?? .movie(path: path, name: canonicalFormat(path), year: 0)
}

/// Matches an already canonical name. Returns nil when nothing matched (Python's "movie_fallback").
func matchVideo(path: String, video: String) -> MediaMatch? {
    if let groups = Patterns.dates.lazy.compactMap({ $0.groups(matching: video) }).first,
       let year = groups.int("year"), let month = groups.int("month"), let day = groups.int("day"),
       Day(year: year, month: month, day: day).isValid {
        let name = canonicalFormat(groups["name"])
        if !name.isEmpty {
            return .tvShow(path: path, name: name, number: .aired(year: year, month: month, day: day))
        }
    }

    if let groups = Patterns.seasonEpisodes.lazy.compactMap({ $0.groups(matching: video) }).first,
       let season = groups.int("season"), let episode = groups.int("episode") {
        let name = canonicalFormat(groups["name"])
        if !name.isEmpty {
            return .tvShow(path: path, name: name, number: .seasonEpisode(season: season, episode: episode))
        }
    }

    if let groups = Patterns.years.lazy.compactMap({ $0.groups(matching: video) }).first {
        return .movie(path: path, name: canonicalFormat(groups["name"]), year: groups.int("year") ?? 0)
    }
    return nil
}

/// Python's `os.path.splitext`, except that an "extension" at least as long as the rest of the name
/// isn't treated as one (so `Glee S3.E18` loses `.E18` but `a.avi` keeps its name intact).
/// The extension includes the dot.
public func splitExtension(_ path: String) -> (name: String, ext: String) {
    let scalars = path.unicodeScalars
    let fileNameStart = scalars.lastIndex(of: "/").map(scalars.index(after:)) ?? scalars.startIndex
    guard let dot = scalars[fileNameStart...].lastIndex(of: "."),
          scalars[fileNameStart..<dot].contains(where: { $0 != "." }) else {
        return (path, "")
    }
    let name = String(scalars[..<dot])
    let ext = String(scalars[dot...])
    return name.unicodeScalars.count > ext.unicodeScalars.count ? (name, ext) : (path, "")
}

/// Whether the file name has one of the `supportedFileFormats` extensions.
public func hasSupportedExtension(_ path: String) -> Bool {
    supportedFileFormats.contains(splitExtension(path).ext.lowercased())
}

/// Strips release junk from a movie name before looking it up: everything from the first
/// `720p`, `[`, `(`, `bluray`, `dvdrip` etc.
func cleanMovieName(_ name: String) -> String {
    var s = name.lowercased().replacingOccurrences(of: ".", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    for tag in ["720p", "[", "(", "bluray", "blu-ray", "brrip", "dvdrip", "bdrip", "dircut"] {
        if let range = s.range(of: tag) {
            s = String(s[..<range.lowerBound])
        }
    }
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Regexes

private enum Patterns {
    static let seasonEpisodes = [
        #"(?<name>.*?) season (?<season>\d\d?) s? ?(\2)?ep? ?(?<episode>\d\d?)"#,
        #"(?<name>.*?) season (?<season>\d\d?) episode (?<episode>\d\d?)"#,
        #"(?<name>.*[^0-9]) season (?<season>\d\d?) (\2)x(?<episode>\d\d?)"#,

        #"(?<name>.*?) series (?<season>\d\d?) s? ?(\2)?ep? ?(?<episode>\d\d?)"#,
        #"(?<name>.*?) series (?<season>\d\d?) episode (?<episode>\d\d?)"#,
        #"(?<name>.*[^0-9]) series (?<season>\d\d?) (\2)x(?<episode>\d\d?)"#,

        #"(?<name>.*)\s?s ?(?<season>\d\d?)\s?ep? ?(?<episode>\d\d?)"#,
        #"(?<name>.*[^0-9])\s?(?<season>\d\d?)x(?<episode>\d\d?)"#,
    ].map(Pattern.init)

    static let dates = [
        #"(?<name>.*)(?<year>\d\d\d\d) (?<month>\d\d) (?<day>\d\d)"#,
    ].map(Pattern.init)

    static let years = [
        #"(?<name>.*) (?<year>19\d\d)"#,
        #"(?<name>.*) (?<year>20\d\d)"#,
        #"(?<name>.*) (?<year>21\d\d)"#,
        // Pseudo matches for common suffixes, so these are movies without a year
        #"(?<name>.*) dvdrip(?<year>)"#,
        #"(?<name>.*) bluray(?<year>)"#,
        #"(?<name>.*) xvid(?<year>)"#,
    ].map(Pattern.init)

    // `^` only matches at the very start, so only the first bracketed prefix is removed, like Python's re.sub.
    static let canonicalRemove = Pattern(#"^\[[^\]]*\]|^\([^\)]*\)|^www\.[a-z]+\.[a-z]{2,3}|'"#)
    static let canonicalSpace = Pattern(#"[/._\-:()\[\]]| 720p ?| 1080p ?| x264 ?"#)
    static let spaces = Pattern(" +")
}

/// A compiled regex. NSRegularExpression is immutable and documented as thread safe.
private struct Pattern: @unchecked Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String) {
        regex = try! NSRegularExpression(pattern: pattern)
    }

    /// Like Python's `re.match`: anchored at the start only.
    func groups(matching s: String) -> Groups? {
        let ns = s as NSString
        guard let match = regex.firstMatch(in: s, options: .anchored, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return Groups(string: ns, match: match)
    }

    func replacingMatches(in s: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }
}

private struct Groups {
    let string: NSString
    let match: NSTextCheckingResult

    subscript(name: String) -> String {
        let range = match.range(withName: name)
        return range.location == NSNotFound ? "" : string.substring(with: range)
    }

    func int(_ name: String) -> Int? {
        Int(self[name])
    }
}
