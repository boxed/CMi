import Foundation

/// The tables exactly as Django creates them (`manage.py sqlmigrate tvshows 0001` / `movies 0001`),
/// so the old Django app and this one can share `cmi.db`.
enum DjangoSchema {
    struct App {
        var label: String
        var migration: String
        var tables: [String]
        var sql: String
    }

    static let apps = [
        App(label: "tvshows", migration: "0001_initial",
            tables: ["tvshows_category", "tvshows_suggestedshow", "tvshows_show", "tvshows_episode"],
            sql: """
            CREATE TABLE IF NOT EXISTS "tvshows_category" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "name" varchar(255) NOT NULL);
            CREATE TABLE IF NOT EXISTS "tvshows_suggestedshow" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "name" varchar(200) NOT NULL UNIQUE, "ignored" bool NOT NULL);
            CREATE TABLE IF NOT EXISTS "tvshows_show" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "name" varchar(200) NOT NULL UNIQUE, "description" text NOT NULL, "canonical_name" varchar(200) NOT NULL, "auto_erase" bool NOT NULL, "source" varchar(255) NOT NULL, "ended" bool NOT NULL, "category_id" integer NULL REFERENCES "tvshows_category" ("id") DEFERRABLE INITIALLY DEFERRED);
            CREATE TABLE IF NOT EXISTS "tvshows_episode" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "name" varchar(200) NOT NULL, "season" integer NOT NULL, "episode" integer NOT NULL, "aired" date NULL, "description" text NULL, "watched" bool NOT NULL, "position" real NOT NULL, "filepath" text NOT NULL, "watched_count" integer NOT NULL, "watched_at" datetime NOT NULL, "show_id" integer NOT NULL REFERENCES "tvshows_show" ("id") DEFERRABLE INITIALLY DEFERRED);
            CREATE INDEX IF NOT EXISTS "tvshows_show_category_id_65f12f32" ON "tvshows_show" ("category_id");
            CREATE INDEX IF NOT EXISTS "tvshows_episode_show_id_a909dfaf" ON "tvshows_episode" ("show_id");
            """),
        App(label: "movies", migration: "0001_initial",
            tables: ["movies_movie"],
            sql: """
            CREATE TABLE IF NOT EXISTS "movies_movie" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "name" varchar(200) NOT NULL, "aired" varchar(200) NOT NULL, "watched" bool NOT NULL, "position" real NOT NULL, "filepath" text NOT NULL);
            """),
    ]

    /// Creates any missing tables. When an app's tables are created from scratch, its migration is also
    /// recorded in `django_migrations`, so running the Django app's `migrate` on the file afterwards
    /// doesn't try to create them again.
    static func install(on connection: SQLiteConnection) throws {
        let existing = Set(try connection.query("SELECT name FROM sqlite_master WHERE type = 'table'") { $0.string(0) })
        try connection.transaction {
            for app in apps {
                let isNew = app.tables.allSatisfy { !existing.contains($0) }
                try connection.execute(app.sql)
                guard isNew else { continue }
                try connection.execute("""
                    CREATE TABLE IF NOT EXISTS "django_migrations" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "app" varchar(255) NOT NULL, "name" varchar(255) NOT NULL, "applied" datetime NOT NULL);
                    """)
                let recorded = try connection.query("SELECT 1 FROM django_migrations WHERE app = ? AND name = ?",
                                                    [app.label, app.migration]) { _ in true }
                if recorded.isEmpty {
                    try connection.run("INSERT INTO django_migrations (app, name, applied) VALUES (?, ?, ?)",
                                       [app.label, app.migration, DjangoDateTime.string(from: Date())])
                }
            }
        }
    }
}

/// Django `DateTimeField` values with `USE_TZ = False`: naive local time as `"YYYY-MM-DD HH:MM:SS[.ffffff]"`.
public enum DjangoDateTime {
    /// The default `watched_at` of an episode: 1970-01-01 00:00:00 local time.
    public static var neverWatched: Date {
        date(from: "1970-01-01 00:00:00")!
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    static func string(from date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        var s = "\(c.year!.zeroPadded(4))-\(c.month!.zeroPadded(2))-\(c.day!.zeroPadded(2)) "
            + "\(c.hour!.zeroPadded(2)):\(c.minute!.zeroPadded(2)):\(c.second!.zeroPadded(2))"
        let microseconds = min((c.nanosecond! + 500) / 1000, 999_999)
        if microseconds != 0 {
            s += "." + microseconds.zeroPadded(6)
        }
        return s
    }

    static func date(from string: String) -> Date? {
        let parts = string.split(whereSeparator: { $0 == " " || $0 == "T" })
        guard let first = parts.first, let day = Day(first) else { return nil }
        var components = DateComponents(year: day.year, month: day.month, day: day.day, hour: 0, minute: 0, second: 0)
        if parts.count > 1 {
            let time = parts[1].split(separator: ".", maxSplits: 1)
            let hms = time[0].split(separator: ":").map { Int($0) }
            guard hms.count == 3, let hour = hms[0], let minute = hms[1], let second = hms[2] else { return nil }
            components.hour = hour
            components.minute = minute
            components.second = second
            if time.count == 2 {
                // Pad/truncate the fraction to microseconds.
                let digits = String(time[1].prefix(6)).padding(toLength: 6, withPad: "0", startingAt: 0)
                guard let microseconds = Int(digits) else { return nil }
                components.nanosecond = microseconds * 1000
            }
        }
        return calendar.date(from: components)
    }
}
