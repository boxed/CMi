import Foundation
import CMiCore

/// The TV shows and movies sorted out of the downloads folder.
@MainActor
struct LocalMenus {
    let database: Database
    let library: Library

    // MARK: TV shows

    func tvShowsTile(category: CMiCore.Category?) -> MenuItem {
        let counts = database.episodeCounts(in: category?.id)
        return MenuItem(title: category?.name ?? "TV Shows", subtitle: "\(counts.new) new / \(counts.total) total",
                        symbol: "tv", action: .open { tvShows(in: category) })
    }

    /// Shows in columns, with any newly found shows to add at the top (tvshows/index.html).
    func tvShows(in category: CMiCore.Category?) -> Menu {
        var rows: [[Cell]] = []
        let suggestions = database.suggestedShows()
        if !suggestions.isEmpty {
            rows.append([.label("Found new shows:")])
            for suggestion in suggestions {
                rows.append([.label(suggestion.name)])
                rows.append([
                    .tile(MenuItem(title: "Add", extra: "and remove watched", action: .run { [library] in
                        await library.addSuggestedShow(suggestion.id, autoErase: true)
                        return .refresh
                    })),
                    .tile(MenuItem(title: "Add", extra: "and keep all", action: .run { [library] in
                        await library.addSuggestedShow(suggestion.id, autoErase: false)
                        return .refresh
                    })),
                    .tile(MenuItem(title: "Ignore", action: .run { [database] in
                        database.ignoreSuggestedShow(suggestion.id)
                        return .refresh
                    })),
                ])
            }
            rows.append([.empty])
        }

        let shows = database.shows(in: category?.id).map { show in
            MenuItem(title: show.name, extra: String(database.unwatchedEpisodeCount(of: show.id)),
                     action: .open { episodes(of: show) })
        }
        if case .table(let columns) = Menu.columns(nil, shows).layout {
            rows += columns
        }
        return Menu(title: category?.name ?? "TV Shows", layout: .table(rows))
    }

    /// Episodes in a column per season, with the next one to watch on top (tvshows/show.html).
    func episodes(of show: Show) -> Menu? {
        let episodes = database.watchableEpisodes(of: show.id)
        guard !episodes.isEmpty else { return nil }
        let tile = { (episode: Episode, prefix: String) in
            MenuItem(title: prefix + episode.displayTitle, unwatchedMarker: !show.autoErase && !episode.watched,
                     action: .play { playable(episode, of: show) })
        }
        let next = database.nextEpisode(of: show.id).map { tile($0, "Next: ") }
        return seasonGrid(title: show.name, episodes: episodes, season: \.season, next: next) { tile($0, "") }
    }

    private func playable(_ episode: Episode, of show: Show) -> Playable {
        Playable(title: "\(show.name) \(episode.displayTitle)", url: URL(fileURLWithPath: episode.filepath),
                 startMilliseconds: Int(episode.position),
                 reportPosition: { [database] in database.setEpisodePosition(episode.id, milliseconds: Double($0)) },
                 reportEnded: { [database] in database.episodeEnded(episode.id) },
                 subtitlesKey: "show:\(show.id)")
    }

    // MARK: Movies

    func moviesTile() -> MenuItem {
        let counts = database.movieCounts()
        return MenuItem(title: "Movies", subtitle: "\(counts.new) new / \(counts.total) total", symbol: "film",
                        action: .open { movies() })
    }

    func movies() -> Menu {
        let movies = database.unwatchedMovies().map(movieItem)
        return movies.isEmpty ? .message("Movies", "No new movies") : .list("Movies", movies)
    }

    private func movieItem(_ movie: Movie) -> MenuItem {
        MenuItem(title: movie.name, extra: movie.aired, action: .play { [database] in
            Playable(title: movie.name, url: URL(fileURLWithPath: movie.filepath), startMilliseconds: Int(movie.position),
                     reportPosition: { database.setMoviePosition(movie.id, milliseconds: Double($0)) },
                     reportEnded: { database.movieEnded(movie.id) },
                     subtitlesKey: "movie:\(movie.id)")
        })
    }

    // MARK: Search

    /// Shows with something to watch, and every movie, whose name contains `query` (ignoring case and accents).
    func search(_ query: String) -> (shows: [MenuItem], movies: [MenuItem]) {
        let categories: [CMiCore.Category?] = [nil] + database.categories().map { $0 }
        let shows = categories.flatMap { database.shows(in: $0?.id) }
            .filter { $0.name.localizedStandardContains(query) }
            .map { show in MenuItem(title: show.name, extra: String(database.unwatchedEpisodeCount(of: show.id)),
                                    action: .open { episodes(of: show) }) }
        let movies = database.allMovies().filter { $0.name.localizedStandardContains(query) }.map(movieItem)
        return (shows, movies)
    }
}

/// Lays out episodes in one column per season under "Season N" labels, with an optional
/// "next episode" tile in its own row first. Shared by local and Plex shows.
@MainActor
func seasonGrid<E>(title: String, episodes: [E], season: (E) -> Int, next: MenuItem?, tile: (E) -> MenuItem) -> Menu {
    let seasons = Array(Set(episodes.map(season))).sorted()
    return columnGrid(title: title, columns: seasons.map { s in ("Season \(s)", episodes.filter { season($0) == s }.map(tile)) }, next: next)
}

/// Columns of tiles under labels, with an optional "next episode" tile in its own row first.
@MainActor
func columnGrid(title: String, columns: [(label: String, items: [MenuItem])], next: MenuItem?) -> Menu {
    var rows: [[Cell]] = [columns.map { .label($0.label) }]
    if let next {
        rows.append([.tile(next)])
    }
    for i in 0..<(columns.map(\.items.count).max() ?? 0) {
        rows.append(columns.map { i < $0.items.count ? .tile($0.items[i]) : .empty })
    }
    return Menu(title: title, layout: .table(rows))
}
