import Foundation
import Testing
@testable import CMiCore

/// A database made by the Django app: `manage.py migrate` on an empty file, then sample rows created through
/// the Django models (scratch script make_fixture.py), dumped with `sqlite3 .dump` (only CMi's tables and
/// migration records, the auth/session tables are irrelevant here).
private let djangoDump = #"""
CREATE TABLE IF NOT EXISTS "movies_movie" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "name" varchar(200) NOT NULL, "aired" varchar(200) NOT NULL, "watched" bool NOT NULL, "position" real NOT NULL, "filepath" text NOT NULL);
INSERT INTO movies_movie VALUES(1,'Iron Man','2008',0,0.0,'/x/iron.mkv');
INSERT INTO movies_movie VALUES(2,'Nine','',1,1000.0,'/x/nine.mkv');
CREATE TABLE IF NOT EXISTS "tvshows_category" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "name" varchar(255) NOT NULL);
INSERT INTO tvshows_category VALUES(1,'Kids');
CREATE TABLE IF NOT EXISTS "tvshows_suggestedshow" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "name" varchar(200) NOT NULL UNIQUE, "ignored" bool NOT NULL);
INSERT INTO tvshows_suggestedshow VALUES(1,'Glee',0);
INSERT INTO tvshows_suggestedshow VALUES(2,'Smash',1);
CREATE TABLE IF NOT EXISTS "tvshows_show" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "name" varchar(200) NOT NULL UNIQUE, "description" text NOT NULL, "canonical_name" varchar(200) NOT NULL, "auto_erase" bool NOT NULL, "source" varchar(255) NOT NULL, "ended" bool NOT NULL, "category_id" integer NULL REFERENCES "tvshows_category" ("id") DEFERRABLE INITIALLY DEFERRED);
INSERT INTO tvshows_show VALUES(1,'House','A doctor.','house',1,'',0,NULL);
INSERT INTO tvshows_show VALUES(2,'Hey Duggee','','hey duggee',0,'',0,1);
INSERT INTO tvshows_show VALUES(3,'The Colbert Report','','the colbert report',0,'',1,NULL);
CREATE TABLE IF NOT EXISTS "tvshows_episode" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "name" varchar(200) NOT NULL, "season" integer NOT NULL, "episode" integer NOT NULL, "aired" date NULL, "description" text NULL, "watched" bool NOT NULL, "position" real NOT NULL, "filepath" text NOT NULL, "watched_count" integer NOT NULL, "watched_at" datetime NOT NULL, "show_id" integer NOT NULL REFERENCES "tvshows_show" ("id") DEFERRABLE INITIALLY DEFERRED);
INSERT INTO tvshows_episode VALUES(1,'Pilot',1,1,NULL,NULL,1,0.0,'/x/House S01E01.avi',1,'2020-05-06 07:08:09.123456',1);
INSERT INTO tvshows_episode VALUES(2,'Paternity',1,2,NULL,NULL,0,12345.5,'/x/House S01E02.avi',0,'1970-01-01 00:00:00',1);
INSERT INTO tvshows_episode VALUES(3,'',1,3,NULL,NULL,0,0.0,'',0,'1970-01-01 00:00:00',1);
INSERT INTO tvshows_episode VALUES(4,'The Stick Badge',1,1,NULL,NULL,1,0.0,'/x/d1.mp4',2,'2021-01-02 03:04:05',2);
INSERT INTO tvshows_episode VALUES(5,'',1,2,NULL,NULL,0,0.0,'/x/d2.mp4',0,'1970-01-01 00:00:00',2);
INSERT INTO tvshows_episode VALUES(6,'James B Stewart',2011,0,'2011-05-31',NULL,0,0.0,'/x/c.avi',0,'1970-01-01 00:00:00',3);
CREATE TABLE IF NOT EXISTS "django_migrations" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "app" varchar(255) NOT NULL, "name" varchar(255) NOT NULL, "applied" datetime NOT NULL);
INSERT INTO django_migrations VALUES(18,'movies','0001_initial','2026-10-29 20:28:10.129834');
INSERT INTO django_migrations VALUES(20,'tvshows','0001_initial','2026-10-29 20:28:10.134233');
CREATE INDEX "tvshows_show_category_id_65f12f32" ON "tvshows_show" ("category_id");
CREATE INDEX "tvshows_episode_show_id_a909dfaf" ON "tvshows_episode" ("show_id");
"""#

struct DjangoCompatibilityTests {
    let database: Database
    let url: URL

    init() throws {
        url = try makeScratchFolder("DjangoCompatibility").appending(path: "cmi.db")
        try SQLiteConnection(path: url.path(percentEncoded: false)).execute(djangoDump)
        database = try Database(url: url)
    }

    @Test func readsShowsAndCategories() throws {
        #expect(database.categories() == [Category(id: 1, name: "Kids")])
        #expect(database.shows(in: nil) == [
            Show(id: 3, name: "The Colbert Report", canonicalName: "the colbert report", autoErase: false, ended: true),
            Show(id: 1, name: "House", description: "A doctor.", canonicalName: "house", autoErase: true),
        ])
        #expect(database.shows(in: 1).map(\.name) == ["Hey Duggee"])
    }

    @Test func readsEpisodes() throws {
        let pilot = try #require(database.episode(1))
        #expect(pilot.name == "Pilot")
        #expect(pilot.watched)
        #expect(pilot.watchedCount == 1)
        #expect(pilot.aired == nil)
        #expect(pilot.description == nil)
        #expect(DjangoDateTime.string(from: pilot.watchedAt) == "2020-05-06 07:08:09.123456")

        #expect(database.episode(2)?.position == 12345.5)
        #expect(database.episode(2)?.watchedAt == DjangoDateTime.neverWatched)

        let colbert = try #require(database.episode(6))
        #expect(colbert.aired == Day(year: 2011, month: 5, day: 31))
        #expect(colbert.displayTitle == "2011-05-31 - James B Stewart")

        #expect(database.watchableEpisodes(of: 1).map(\.id) == [2])  // auto erase: watched pilot is hidden
        #expect(database.watchableEpisodes(of: 2).map(\.id) == [4, 5])
        #expect(database.nextEpisode(of: 2)?.id == 5)
        #expect(database.unwatchedEpisodeCount(of: 2) == 1)
        #expect(database.episodeCounts(in: nil) == (new: 2, total: 3))
        #expect(database.episodeCounts(in: 1) == (new: 1, total: 2))
    }

    @Test func readsMoviesAndSuggestions() {
        #expect(database.unwatchedMovies() == [Movie(id: 1, name: "Iron Man", aired: "2008", filepath: "/x/iron.mkv")])
        #expect(database.movieCounts() == (new: 1, total: 2))
        #expect(database.suggestedShows() == [SuggestedShow(id: 1, name: "Glee")])
    }

    @Test func writesTheWayDjangoDoes() throws {
        database.episodeEnded(2)
        database.setMoviePosition(1, milliseconds: 42)
        let show = try #require(database.insertShow(name: "Glee", autoErase: false))
        database.insertEpisode(show: show, season: 3, episode: 6, aired: nil, filepath: "/g")

        let raw = try SQLiteConnection(path: url.path(percentEncoded: false))
        let episode = try raw.query("SELECT typeof(watched), watched, watched_count, position, watched_at FROM tvshows_episode WHERE id = 2") {
            [$0.string(0), $0.string(1), $0.string(2), $0.string(3), $0.string(4)]
        }.first!
        #expect(Array(episode[0...3]) == ["integer", "1", "1", "0.0"])
        // "YYYY-MM-DD HH:MM:SS[.ffffff]"
        #expect(episode[4].wholeMatch(of: /\d{4}-\d\d-\d\d \d\d:\d\d:\d\d(\.\d{6})?/) != nil)

        let newEpisode = try raw.query("SELECT name, typeof(aired), description IS NULL, watched, watched_count, watched_at FROM tvshows_episode WHERE filepath = '/g'") {
            [$0.string(0), $0.string(1), $0.string(2), $0.string(3), $0.string(4), $0.string(5)]
        }.first!
        #expect(newEpisode == ["", "null", "1", "0", "0", "1970-01-01 00:00:00"])

        let newShow = try raw.query("SELECT canonical_name, auto_erase, source, ended, category_id IS NULL FROM tvshows_show WHERE name = 'Glee'") {
            [$0.string(0), $0.string(1), $0.string(2), $0.string(3), $0.string(4)]
        }.first!
        #expect(newShow == ["glee", "0", "", "0", "1"])
        #expect(try raw.query("SELECT position FROM movies_movie WHERE id = 1") { $0.double(0) } == [42])
    }

    @Test func doesNotTouchAnExistingSchema() throws {
        let raw = try SQLiteConnection(path: url.path(percentEncoded: false))
        #expect(try raw.query("SELECT COUNT(*) FROM django_migrations") { $0.int(0) } == [2])
    }
}
