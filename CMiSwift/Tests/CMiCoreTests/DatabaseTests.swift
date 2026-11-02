import Foundation
import Testing
@testable import CMiCore

struct DatabaseTests {
    let database: Database
    let folder: URL

    init() throws {
        folder = try makeScratchFolder("DatabaseTests")
        database = try Database(url: folder.appending(path: "cmi.db"))
    }

    @Test func emptyDatabase() {
        #expect(database.categories().isEmpty)
        #expect(database.shows(in: nil).isEmpty)
        #expect(database.unwatchedMovies().isEmpty)
        #expect(database.suggestedShows().isEmpty)
        #expect(database.episodeCounts(in: nil) == (0, 0))
        #expect(database.movieCounts() == (0, 0))
        #expect(database.episode(1) == nil)
    }

    @Test func reopeningKeepsData() throws {
        let id = database.insertShow(name: "House")
        let reopened = try Database(url: folder.appending(path: "cmi.db"))
        #expect(reopened.show(id!)?.name == "House")
        #expect(reopened.show(canonicalName: "house")?.id == id)
    }

    @Test func showsHaveWatchableEpisodesAndSortIgnoringThe() throws {
        let kids = try #require(database.insertCategory(name: "Kids"))
        let house = try #require(database.insertShow(name: "House", autoErase: true))
        let office = try #require(database.insertShow(name: "The Office", autoErase: false))
        let archer = try #require(database.insertShow(name: "Archer", autoErase: true))
        let empty = try #require(database.insertShow(name: "Empty"))
        let duggee = try #require(database.insertShow(name: "Hey Duggee", category: kids))

        database.insertEpisode(show: house, season: 1, episode: 1, filepath: "/h1")
        database.insertEpisode(show: office, season: 1, episode: 1, filepath: "/o1", watched: true)  // keep: still watchable
        database.insertEpisode(show: archer, season: 1, episode: 1, filepath: "/a1", watched: true)  // auto erase: not watchable
        database.insertEpisode(show: empty, season: 1, episode: 1)  // no file
        database.insertEpisode(show: duggee, season: 1, episode: 1, filepath: "/d1")

        #expect(database.shows(in: nil).map(\.name) == ["House", "The Office"])
        #expect(database.shows(in: kids).map(\.name) == ["Hey Duggee"])
        #expect(database.categories() == [Category(id: kids, name: "Kids")])
        #expect(database.insertShow(name: "House") == nil)  // names are unique
    }

    @Test func watchableEpisodesAndCounts() throws {
        let erase = try #require(database.insertShow(name: "Erase", autoErase: true))
        let keep = try #require(database.insertShow(name: "Keep", autoErase: false))
        for show in [erase, keep] {
            database.insertEpisode(show: show, season: 2, episode: 1, filepath: "/2-1")
            database.insertEpisode(show: show, season: 1, episode: 2, filepath: "/1-2", watched: true)
            database.insertEpisode(show: show, season: 1, episode: 1, filepath: "/1-1")
            database.insertEpisode(show: show, season: 1, episode: 3)  // no file
        }
        #expect(database.watchableEpisodes(of: erase).map(\.filepath) == ["/1-1", "/2-1"])
        #expect(database.watchableEpisodes(of: keep).map(\.filepath) == ["/1-1", "/1-2", "/2-1"])
        #expect(database.unwatchedEpisodeCount(of: erase) == 2)
        #expect(database.unwatchedEpisodeCount(of: keep) == 2)
        #expect(database.episodeCounts(in: nil) == (new: 4, total: 6))
    }

    @Test func nextEpisode() throws {
        let show = try #require(database.insertShow(name: "Keep", autoErase: false))
        let e1 = try #require(database.insertEpisode(show: show, season: 1, episode: 1, filepath: "/1"))
        let e2 = try #require(database.insertEpisode(show: show, season: 1, episode: 2, filepath: "/2"))
        let e3 = try #require(database.insertEpisode(show: show, season: 1, episode: 3, filepath: "/3"))

        // Nothing watched: the first episode is the obvious choice, so no "next".
        #expect(database.nextEpisode(of: show) == nil)

        database.episodeEnded(e1)
        #expect(database.nextEpisode(of: show)?.id == e2)
        database.episodeEnded(e2)
        #expect(database.nextEpisode(of: show)?.id == e3)
        database.episodeEnded(e3)
        // All watched: the one watched longest ago, which is the first again.
        #expect(database.nextEpisode(of: show) == nil)
        database.episodeEnded(e1)
        #expect(database.nextEpisode(of: show)?.id == e2)
    }

    @Test func episodeEndedAndPosition() throws {
        let show = try #require(database.insertShow(name: "House"))
        let id = try #require(database.insertEpisode(show: show, season: 1, episode: 1, filepath: "/x"))
        var episode = try #require(database.episode(id))
        #expect(!episode.watched)
        #expect(episode.watchedCount == 0)
        #expect(episode.watchedAt == DjangoDateTime.neverWatched)
        #expect(episode.description == nil)

        database.setEpisodePosition(id, milliseconds: 123_456.5)
        #expect(database.episode(id)?.position == 123_456.5)

        let before = Date()
        database.episodeEnded(id)
        episode = try #require(database.episode(id))
        #expect(episode.watched)
        #expect(episode.watchedCount == 1)
        #expect(episode.position == 0)
        #expect(abs(episode.watchedAt.timeIntervalSince(before)) < 5)
        database.episodeEnded(id)
        #expect(database.episode(id)?.watchedCount == 2)
    }

    @Test func movies() throws {
        let iron = try #require(database.insertMovie(name: "Iron Man", aired: "2008", filepath: "/iron.mkv"))
        database.insertMovie(name: "Amelie", filepath: "/amelie.mkv")
        database.insertMovie(name: "Old", filepath: "/old.mkv", watched: true)
        #expect(database.unwatchedMovies().map(\.name) == ["Amelie", "Iron Man"])
        #expect(database.movieCounts() == (new: 2, total: 3))

        database.setMoviePosition(iron, milliseconds: 5000)
        #expect(database.movie(iron)?.position == 5000)
        database.movieEnded(iron)
        #expect(database.movie(iron)?.watched == true)
        #expect(database.movieCounts() == (new: 1, total: 3))
        #expect(database.unwatchedMovies().map(\.name) == ["Amelie"])
    }

    @Test func suggestedShows() throws {
        let glee = try #require(database.insertSuggestedShow(name: "Glee"))
        database.insertSuggestedShow(name: "Awake")
        #expect(database.insertSuggestedShow(name: "Glee") == nil)
        #expect(database.suggestedShows().map(\.name) == ["Awake", "Glee"])
        database.ignoreSuggestedShow(glee)
        #expect(database.suggestedShows().map(\.name) == ["Awake"])
        #expect(database.suggestedShow(glee)?.ignored == true)
    }

    @Test func displayTitles() {
        #expect(Episode(id: 1, showID: 1, name: "Pilot", season: 1, episode: 3).displayTitle == "3. Pilot")
        #expect(Episode(id: 1, showID: 1, season: 1, episode: 3).displayTitle == "3")
        let aired = Day(year: 2011, month: 5, day: 31)
        #expect(Episode(id: 1, showID: 1, name: "Guest", season: 2011, aired: aired).displayTitle == "2011-05-31 - Guest")
        #expect(Episode(id: 1, showID: 1, season: 2011, aired: aired).displayTitle == "2011-05-31")
    }

    @Test func djangoDateTimes() throws {
        let date = try #require(DjangoDateTime.date(from: "2020-05-06 07:08:09.123456"))
        #expect(DjangoDateTime.string(from: date) == "2020-05-06 07:08:09.123456")
        let whole = try #require(DjangoDateTime.date(from: "2021-01-02 03:04:05"))
        #expect(DjangoDateTime.string(from: whole) == "2021-01-02 03:04:05")
        #expect(DjangoDateTime.date(from: "1970-01-01 00:00:00") == DjangoDateTime.neverWatched)
    }

    @Test func newDatabaseIsRecordedAsMigratedForDjango() throws {
        let rows = try SQLiteConnection(path: folder.appending(path: "cmi.db").path(percentEncoded: false))
            .query("SELECT app, name FROM django_migrations ORDER BY app") { "\($0.string(0)) \($0.string(1))" }
        #expect(rows == ["movies 0001_initial", "tvshows 0001_initial"])
    }
}
