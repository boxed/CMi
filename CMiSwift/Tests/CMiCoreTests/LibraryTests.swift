import Foundation
import Testing
@testable import CMiCore

struct LibraryTests {
    let paths: Paths
    let database: Database
    let metadata = StubMetadata()
    let trash = TrashRecorder()
    let library: Library

    init() throws {
        let root = try makeScratchFolder("LibraryTests")
        paths = Paths(supportFolder: root.appending(path: "Support"), downloads: root.appending(path: "Downloads"))
        try FileManager.default.createDirectory(at: paths.downloads, withIntermediateDirectories: true)
        database = try Database(url: paths.database)
        library = Library(paths: paths, database: database, metadata: metadata, trash: trash.trash)
    }

    private func download(_ relativePath: String) throws {
        try makeVideo(paths.downloads.appending(path: relativePath))
    }

    @Test func filesEpisodesOfKnownShowsAndFetchesTheirNames() async throws {
        let house = try #require(database.insertShow(name: "House"))
        let colbert = try #require(database.insertShow(name: "The Colbert Report"))
        try download("House.S08E03.HDTV.XviD-LOL.avi")
        try download("The.Colbert.Report.2011.05.31.James.B.Stewart.HDTV.XviD-FQM.[VTV].avi")
        metadata.shows["house"] = [ShowInfo(id: 118, name: "House")]
        metadata.episodes[118] = [
            EpisodeInfo(id: 1, name: "Wrong", season: 8, number: 3),
            EpisodeInfo(id: 2, name: "Parents", season: 8, number: 3, overview: "Kids."),  // later wins, like Python
        ]
        metadata.shows["the colbert report"] = [ShowInfo(id: 9, name: "The Colbert Report")]
        metadata.episodes[9] = [EpisodeInfo(id: 3, name: "James B. Stewart", season: 7, number: 70, airdate: Day("2011-05-31"))]

        #expect(await library.scan())

        let houseFile = paths.tvShows.appending(path: "House/Season 8/house S08E03.avi")
        let colbertFile = paths.tvShows.appending(path: "The Colbert Report/Season 2011/the colbert report 2011-05-31.avi")
        #expect(exists(houseFile))
        #expect(exists(colbertFile))
        #expect(!exists(paths.downloads.appending(path: "House.S08E03.HDTV.XviD-LOL.avi")))

        let houseEpisode = try #require(database.watchableEpisodes(of: house).first)
        #expect(houseEpisode.season == 8 && houseEpisode.episode == 3 && houseEpisode.aired == nil)
        #expect(houseEpisode.filepath == houseFile.path(percentEncoded: false))
        #expect(houseEpisode.name == "Parents")
        #expect(houseEpisode.description == "Kids.")

        let colbertEpisode = try #require(database.watchableEpisodes(of: colbert).first)
        #expect(colbertEpisode.season == 2011 && colbertEpisode.episode == 0)
        #expect(colbertEpisode.aired == Day(year: 2011, month: 5, day: 31))
        #expect(colbertEpisode.filepath == colbertFile.path(percentEncoded: false))
        #expect(colbertEpisode.name == "James B. Stewart")

        // Nothing new the second time
        #expect(await library.scan() == false)
    }

    @Test func redownloadedEpisodeReusesTheRow() async throws {
        let house = try #require(database.insertShow(name: "House"))
        let id = try #require(database.insertEpisode(show: house, season: 1, episode: 2, name: "Paternity"))
        try download("House S01E02 [eztv]/House.S01E02.mkv")
        #expect(await library.scan())
        #expect(database.episode(id)?.filepath == paths.tvShows.appending(path: "House/Season 1/house S01E02.mkv").path(percentEncoded: false))
        #expect(database.allEpisodes().count == 1)
    }

    @Test func unknownShowsBecomeSuggestions() async throws {
        try download("Glee.S02E22.HDTV.XviD-LOL.[VTV].avi")
        try download("Glee S03E06 Mash Off HDTV XviD-LOL [eztv].avi")
        try download("Nonexistent.Show.S01E01.avi")
        metadata.shows["glee"] = [ShowInfo(id: 1, name: "Glee Club"), ShowInfo(id: 2, name: "Glee", overview: "Singing.")]

        #expect(await library.scan())
        #expect(database.suggestedShows().map(\.name) == ["Glee"])
        #expect(exists(paths.downloads.appending(path: "Glee.S02E22.HDTV.XviD-LOL.[VTV].avi")))
        // The show not on TVmaze is remembered, the second Glee file found the existing suggestion.
        #expect(metadata.queries.filter { $0 == "show:nonexistent show" }.count == 1)

        // Each file is only tried once
        let queries = metadata.queries.count
        #expect(await library.scan() == false)
        #expect(metadata.queries.count == queries)

        // Adding the suggestion files the episodes on the next scan
        let suggestion = try #require(database.suggestedShows().first)
        await library.addSuggestedShow(suggestion.id, autoErase: false)
        #expect(database.suggestedShows().isEmpty)
        let glee = try #require(database.show(canonicalName: "glee"))
        #expect(glee.name == "Glee")
        #expect(glee.description == "")  // the stub has no answer for "Glee"
        #expect(!glee.autoErase)

        #expect(await library.scan())
        #expect(database.watchableEpisodes(of: glee.id).map(\.filepath) == [
            paths.tvShows.appending(path: "Glee/Season 2/glee S02E22.avi").path(percentEncoded: false),
            paths.tvShows.appending(path: "Glee/Season 3/glee S03E06.avi").path(percentEncoded: false),
        ])
    }

    @Test func addSuggestedShowUsesTheTVmazeSummary() async throws {
        let id = try #require(database.insertSuggestedShow(name: "Awake"))
        metadata.shows["Awake"] = [ShowInfo(id: 5, name: "Awake", overview: "A detective.")]
        await library.addSuggestedShow(id, autoErase: true)
        let show = try #require(database.show(canonicalName: "awake"))
        #expect(show.description == "A detective.")
        #expect(show.autoErase)
    }

    @Test func ignoredSuggestionsAreNotSuggestedAgain() async throws {
        let id = try #require(database.insertSuggestedShow(name: "Glee"))
        database.ignoreSuggestedShow(id)
        try download("Glee.S02E22.avi")
        metadata.shows["glee"] = [ShowInfo(id: 2, name: "Glee")]
        #expect(await library.scan() == false)
        #expect(database.suggestedShows().isEmpty)
    }

    @Test func filesMovies() async throws {
        try download("Iron.Man.2.2010.720p.BluRay.x264-WiKi.mkv")
        try download("Crazy.Stupid.Love.DVDRip.XviD-TWiZTED.avi")
        try download("Midnight.in.Paris.avi")
        try download("Not.A.Real.Movie.avi")
        metadata.titles["iron man 2"] = [TitleInfo(imdbID: "tt1228705", title: "Iron Man 2", year: 2010)]
        // Several titles with the same name: the first (best) one wins
        metadata.titles["crazy stupid love"] = [
            TitleInfo(imdbID: "tt1570728", title: "Crazy Stupid Love", year: 2011),
            TitleInfo(imdbID: "tt0000001", title: "Crazy Stupid Love", year: 1999),
        ]
        // Unrecognizable names keep their extension ("midnight in paris avi"), found by dropping the last word
        metadata.titles["midnight in paris"] = [TitleInfo(imdbID: "tt1605783", title: "Midnight in Paris", year: 2011)]

        #expect(await library.scan())

        let movies = database.unwatchedMovies()
        #expect(movies.map(\.name) == ["Crazy Stupid Love", "Iron Man 2", "Midnight in Paris"])
        #expect(movies.map(\.aired) == ["2011", "2010", "2011"])
        #expect(movies[1].filepath == paths.movies.appending(path: "Iron.Man.2.2010.720p.BluRay.x264-WiKi.mkv").path(percentEncoded: false))
        #expect(movies.allSatisfy { FileManager.default.fileExists(atPath: $0.filepath) })
        #expect(exists(paths.downloads.appending(path: "Not.A.Real.Movie.avi")))
        #expect(metadata.queries.contains("title:midnight in paris avi"))
    }

    @Test func subtitlesMoveWithTheVideo() async throws {
        _ = try #require(database.insertShow(name: "House"))
        // Next to the video, named after it
        try download("House.S08E03.avi")
        try download("House.S08E03.srt")
        try download("House.S08E03.en.srt")
        try download("House.S08E03.HDTV.srt")
        // A release folder with a Subs folder
        try download("House.S08E04.720p/House.S08E04.720p.mkv")
        try download("House.S08E04.720p/Subs/2_English.srt")
        // A season in one folder, with a Subs folder per episode
        try download("House.S07/House.S07E01.mkv")
        try download("House.S07/House.S07E02.mkv")
        try download("House.S07/House.S07E03.mkv")
        try download("House.S07/Subs/House.S07E01/3_Swedish.srt")
        try download("House.S07/Subs/House.S07E02.srt")
        try download("House.S07/Subs/common.srt")   // whose is it?

        #expect(await library.scan())

        let house = paths.tvShows.appending(path: "House")
        #expect(exists(house.appending(path: "Season 8/house S08E03.srt")))
        #expect(exists(house.appending(path: "Season 8/house S08E03.en.srt")))
        #expect(exists(house.appending(path: "Season 8/house S08E03.HDTV.srt")))
        #expect(exists(house.appending(path: "Season 8/house S08E04.2_English.srt")))
        #expect(exists(house.appending(path: "Season 7/house S07E01.3_Swedish.srt")))
        #expect(exists(paths.downloads.appending(path: "House.S07/Subs/common.srt")))
        let season7 = try FileManager.default.contentsOfDirectory(atPath: house.appending(path: "Season 7").path(percentEncoded: false))
        #expect(season7.sorted() == ["house S07E01.3_Swedish.srt", "house S07E01.mkv", "house S07E02.mkv",
                                     "house S07E02.srt", "house S07E03.mkv"])
    }

    @Test func skipsFoldersThatAreNotDownloads() async throws {
        try download("incomplete/House.S08E03.avi")
        try download("Sample/House.S08E04.avi")
        try download("House.S08E05.srt")
        try download(".House.S08E06.avi")
        #expect(findVideos(in: paths.downloads).isEmpty)
        #expect(await library.scan() == false)
        #expect(metadata.queries.isEmpty)
    }

    @Test func networkFailuresAreRetried() async throws {
        try download("Glee.S02E22.avi")
        metadata.failing = true
        #expect(await library.scan() == false)
        metadata.failing = false
        metadata.shows["glee"] = [ShowInfo(id: 2, name: "Glee")]
        #expect(await library.scan())
        #expect(database.suggestedShows().map(\.name) == ["Glee"])
    }

    @Test func trashesWatchedEpisodesOfAutoEraseShows() async throws {
        let erase = try #require(database.insertShow(name: "House", autoErase: true))
        let keep = try #require(database.insertShow(name: "Hey Duggee", autoErase: false))
        let erasedFile = paths.tvShows.appending(path: "House/Season 1/house S01E01.avi")
        let remainingFile = paths.tvShows.appending(path: "House/Season 2/house S02E01.avi")
        let keptFile = paths.tvShows.appending(path: "Hey Duggee/Season 1/hey duggee S01E01.mp4")
        for file in [erasedFile, remainingFile, keptFile] {
            try makeVideo(file, size: 10)
        }
        try Data().write(to: paths.tvShows.appending(path: "House/Season 1/.DS_Store"))
        let erasedSubtitles = paths.tvShows.appending(path: "House/Season 1/house S01E01.en.srt")
        try Data().write(to: erasedSubtitles)
        let erased = try #require(database.insertEpisode(show: erase, season: 1, episode: 1, filepath: erasedFile.path(percentEncoded: false)))
        let remaining = try #require(database.insertEpisode(show: erase, season: 2, episode: 1, name: "x", filepath: remainingFile.path(percentEncoded: false)))
        let kept = try #require(database.insertEpisode(show: keep, season: 1, episode: 1, name: "x", filepath: keptFile.path(percentEncoded: false)))
        database.episodeEnded(erased)
        database.episodeEnded(kept)

        _ = await library.scan()

        #expect(database.episode(erased)?.filepath == "")
        #expect(database.episode(remaining)?.filepath == remainingFile.path(percentEncoded: false))
        #expect(database.episode(kept)?.filepath == keptFile.path(percentEncoded: false))
        // The file, then its (now empty but for .DS_Store) season folder
        #expect(trash.trashed == [
            erasedSubtitles.path(percentEncoded: false),
            erasedFile.path(percentEncoded: false),
            paths.tvShows.appending(path: "House/Season 1", directoryHint: .isDirectory).path(percentEncoded: false),
        ])
        #expect(exists(paths.tvShows.appending(path: "House")))
        #expect(exists(keptFile))
    }

    @Test func forgetsFilesThatAreGone() async throws {
        try FileManager.default.createDirectory(at: paths.tvShows, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.movies, withIntermediateDirectories: true)
        let show = try #require(database.insertShow(name: "House"))
        let episode = try #require(database.insertEpisode(show: show, season: 1, episode: 1, name: "Pilot", filepath: "/nonexistent/house.avi"))
        let movie = try #require(database.insertMovie(name: "Gone", filepath: "/nonexistent/gone.mkv"))
        let presentFile = paths.movies.appending(path: "here.mkv")
        try makeVideo(presentFile, size: 10)
        let present = try #require(database.insertMovie(name: "Here", filepath: presentFile.path(percentEncoded: false)))

        _ = await library.scan()

        #expect(database.episode(episode)?.filepath == "")
        #expect(database.movie(movie) == nil)
        #expect(database.movie(present) != nil)
        #expect(trash.trashed.isEmpty)
    }

    @Test func leavesTheDatabaseAloneWhenTheFoldersAreMissing() async throws {
        let show = try #require(database.insertShow(name: "House"))
        let episode = try #require(database.insertEpisode(show: show, season: 1, episode: 1, name: "Pilot", filepath: "/Volumes/Gone/house.avi"))
        let movie = try #require(database.insertMovie(name: "Gone", filepath: "/Volumes/Gone/gone.mkv"))
        _ = await library.scan()
        #expect(database.episode(episode)?.filepath == "/Volumes/Gone/house.avi")
        #expect(database.movie(movie) != nil)
    }

    @Test func playablePathFindsTheVideoInAFolder() throws {
        let folder = paths.downloads.appending(path: "Some.Movie.2011")
        try makeVideo(folder.appending(path: "Sample/some.movie.sample.mkv"))
        try makeVideo(folder.appending(path: "small.mkv"), size: 10)
        try makeVideo(folder.appending(path: "some.movie.mkv"))
        #expect(playablePath(folder.path(percentEncoded: false)) == folder.appending(path: "some.movie.mkv").path(percentEncoded: false))
        let file = folder.appending(path: "small.mkv").path(percentEncoded: false)
        #expect(playablePath(file) == file)
    }
}
