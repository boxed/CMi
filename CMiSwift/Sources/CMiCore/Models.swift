import Foundation

/// A calendar day without a time or time zone, like Django's `DateField` (stored as `"YYYY-MM-DD"`).
public struct Day: Sendable, Hashable, Comparable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `"YYYY-MM-DD"`. Returns nil for anything else, including impossible dates like 2011-02-30.
    public init?(_ string: some StringProtocol) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        self.init(year: year, month: month, day: day)
        guard isValid else { return nil }
    }

    /// Whether this is a real date (in the range Python's `datetime` accepts, years 1-9999).
    public var isValid: Bool {
        guard (1...9999).contains(year) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return DateComponents(year: year, month: month, day: day).isValidDate(in: calendar)
    }

    /// `"YYYY-MM-DD"`
    public var description: String {
        "\(year.zeroPadded(4))-\(month.zeroPadded(2))-\(day.zeroPadded(2))"
    }

    public static func < (lhs: Day, rhs: Day) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

public struct Category: Sendable, Hashable, Identifiable {
    public var id: Int64
    public var name: String

    public init(id: Int64, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Show: Sendable, Hashable, Identifiable {
    public var id: Int64
    public var name: String
    public var description: String
    /// `canonicalFormat(name)`; what episode file names are matched against.
    public var canonicalName: String
    /// Watched episodes are moved to the trash, and only unwatched episodes are listed.
    public var autoErase: Bool
    public var source: String
    public var ended: Bool
    public var categoryID: Int64?

    public init(id: Int64, name: String, description: String = "", canonicalName: String, autoErase: Bool = true,
                source: String = "", ended: Bool = false, categoryID: Int64? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.canonicalName = canonicalName
        self.autoErase = autoErase
        self.source = source
        self.ended = ended
        self.categoryID = categoryID
    }
}

public struct Episode: Sendable, Hashable, Identifiable {
    public var id: Int64
    public var showID: Int64
    /// Empty until fetched from TVmaze.
    public var name: String
    /// For date based shows (talk shows etc.) this is the year aired.
    public var season: Int
    /// 0 for date based shows; `aired` is set instead.
    public var episode: Int
    public var aired: Day?
    public var description: String?
    public var watched: Bool
    /// Playback position in milliseconds.
    public var position: Double
    /// Absolute path of the video, or empty if the episode has no file (anymore).
    public var filepath: String
    public var watchedCount: Int
    /// When the episode was last watched to the end. 1970-01-01 (local time) if never.
    public var watchedAt: Date

    public init(id: Int64, showID: Int64, name: String = "", season: Int, episode: Int = 0, aired: Day? = nil,
                description: String? = nil, watched: Bool = false, position: Double = 0, filepath: String = "",
                watchedCount: Int = 0, watchedAt: Date = DjangoDateTime.neverWatched) {
        self.id = id
        self.showID = showID
        self.name = name
        self.season = season
        self.episode = episode
        self.aired = aired
        self.description = description
        self.watched = watched
        self.position = position
        self.filepath = filepath
        self.watchedCount = watchedCount
        self.watchedAt = watchedAt
    }

    /// The tile text: `"3. Name"`, or `"2011-05-31 - Name"` for date based episodes. The name part is left out if unknown.
    public var displayTitle: String {
        if episode == 0 {
            let day = aired?.description ?? ""
            return name.isEmpty ? day : "\(day) - \(name)"
        }
        return name.isEmpty ? "\(episode)" : "\(episode). \(name)"
    }
}

public struct Movie: Sendable, Hashable, Identifiable {
    public var id: Int64
    public var name: String
    /// The year as text (that's how the Django app stored it), or empty if unknown.
    public var aired: String
    public var watched: Bool
    /// Playback position in milliseconds.
    public var position: Double
    public var filepath: String

    public init(id: Int64, name: String, aired: String = "", watched: Bool = false, position: Double = 0, filepath: String) {
        self.id = id
        self.name = name
        self.aired = aired
        self.watched = watched
        self.position = position
        self.filepath = filepath
    }
}

/// A show found on TVmaze for a downloaded episode that doesn't belong to any show yet.
public struct SuggestedShow: Sendable, Hashable, Identifiable {
    public var id: Int64
    public var name: String
    public var ignored: Bool

    public init(id: Int64, name: String, ignored: Bool = false) {
        self.id = id
        self.name = name
        self.ignored = ignored
    }
}

/// The sort key for show and movie titles: case insensitive, ignoring a leading "the ".
public func titleSortKey(_ title: String) -> String {
    let lowered = title.lowercased()
    return lowered.hasPrefix("the ") ? String(lowered.dropFirst(4)) : lowered
}

extension Int {
    func zeroPadded(_ width: Int) -> String {
        let digits = String(magnitude)
        let padded = String(repeating: "0", count: Swift.max(0, width - digits.count)) + digits
        return self < 0 ? "-" + padded : padded
    }
}
