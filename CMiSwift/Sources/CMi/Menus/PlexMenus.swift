import Foundation
import CMiPlex

/// Browsing a Plex Media Server, and signing in to one.
@MainActor
struct PlexMenus {
    let plex: Plex
    let signIn: PlexSignIn

    /// How often pages that offer the next episode reload, so something watched on another device
    /// doesn't show up as next here. `CMI_PLEX_SYNC_SECONDS` overrides it (for testing).
    static let syncInterval = ProcessInfo.processInfo.environment["CMI_PLEX_SYNC_SECONDS"].flatMap(TimeInterval.init) ?? 3600

    func tile() async -> MenuItem {
        MenuItem(title: "Plex", subtitle: await plex.serverName ?? "Sign in", symbol: "play.rectangle",
                 action: .open { try await root() })
    }

    /// The libraries, or the sign in steps if not signed in yet.
    func root() async throws -> Menu {
        switch await signIn.start() {
        case .signedIn:
            return try await libraries()
        case .showingCode(let code):
            return Menu(title: "Sign in to Plex", layout: .table([
                [.label("On your phone or computer, go to plex.tv/link and enter:")],
                [.label(code, size: 140)],
            ]), poll: Menu.Poll(interval: 2) {
                // Refresh once anything changes: signed in, choosing a server, or a new code
                if case .showingCode(code) = await signIn.poll() { return false }
                return true
            })
        case .choosingServer(let servers):
            guard !servers.isEmpty else { return .message("Plex", "No Plex servers found on your account") }
            return .list("Choose Plex server", servers.map { server in
                MenuItem(title: server.name, extra: server.owned ? nil : "shared", action: .run {
                    _ = await signIn.choose(server.id)
                    return .refresh
                })
            })
        case .failed(let message):
            return .message("Plex", message)
        }
    }

    /// What you're in the middle of as one row on top, so it's one press to continue, then the libraries.
    private func libraries() async throws -> Menu {
        var rows: [[Cell]] = []
        // Not worth failing the whole menu over
        let onDeck = (try? await plex.onDeck()) ?? []
        if !onDeck.isEmpty {
            rows.append([.label("Continue watching")])
            rows.append(onDeck.map { item in
                .tile(MenuItem(title: item.title, extra: item.episode.map(Self.episodeNumber), action: .play {
                    let title = item.episode.map { "\(item.title) \(Self.episodeNumber($0)) \($0.title)" } ?? item.title
                    return try await playable(item.id, title: title)
                }))
            })
            rows.append([.empty])
        }
        let sections = try await plex.sections().map { section in
            MenuItem(title: section.title, action: .open { try await sectionMenu(section) })
        }
        let signOut = MenuItem(title: "Sign out", extra: await plex.serverName, action: .run {
            await plex.signOut()
            return .refresh
        })
        rows += (sections + [signOut]).map { [.tile($0)] }
        return Menu(title: "Plex", layout: .table(rows), poll: .refresh(every: Self.syncInterval))
    }

    /// "S2E3", or the air date for date based shows.
    private static func episodeNumber(_ episode: PlexEpisode) -> String {
        if let index = episode.index { return "S\(episode.season)E\(index)" }
        return episode.aired ?? ""
    }

    /// Unwatched movies, and shows with unwatched episodes.
    private func sectionMenu(_ section: PlexSection) async throws -> Menu {
        let items = try await plex.items(in: section.id).compactMap { item -> MenuItem? in
            switch item.kind {
            case .movie:
                guard !item.watched else { return nil }
                return MenuItem(title: item.title, extra: item.year.map(String.init), action: .play {
                    try await playable(item.id, title: item.title)
                })
            case .show:
                guard item.unwatchedEpisodes > 0 else { return nil }
                return MenuItem(title: item.title, extra: String(item.unwatchedEpisodes), action: .open {
                    try await episodes(ofShow: item.id)
                })
            }
        }.sorted { titleSortKey($0.title) < titleSortKey($1.title) }
        return items.isEmpty ? .message(section.title, "Nothing new") : .columns(section.title, items)
    }

    private func episodes(ofShow ratingKey: String) async throws -> Menu? {
        let episodes = try await plex.episodes(ofShow: ratingKey)
        guard let first = episodes.first else { return nil }
        let tile = { (episode: PlexEpisode, prefix: String) in
            let number = episode.index.map(String.init) ?? episode.aired ?? ""
            let title = [number, episode.title].filter { !$0.isEmpty }.joined(separator: ". ")
            return MenuItem(title: prefix + title, unwatchedMarker: !episode.watched, action: .play {
                try await playable(episode.id, title: "\(episode.showTitle) \(title)")
            })
        }
        var menu = seasonGrid(title: first.showTitle, episodes: episodes, season: \.season,
                              next: PlexEpisode.next(in: episodes).map { tile($0, "Next: ") }) { tile($0, "") }
        menu.poll = .refresh(every: Self.syncInterval)
        return menu
    }

    /// Matching movies, shows and episodes from the server's own search. Nothing when not signed in.
    func search(_ query: String) async throws -> [MenuItem] {
        guard await plex.isSignedIn else { return [] }
        return try await plex.search(query).map { result in
            switch result {
            case .movie(let movie):
                return MenuItem(title: movie.title, extra: movie.year.map(String.init), action: .play {
                    try await playable(movie.id, title: movie.title)
                })
            case .show(let show):
                return MenuItem(title: show.title, extra: String(show.unwatchedEpisodes), action: .open {
                    try await episodes(ofShow: show.id)
                })
            case .episode(let episode):
                let title = "\(episode.showTitle) \(Self.episodeNumber(episode)) \(episode.title)"
                return MenuItem(title: title, action: .play { try await playable(episode.id, title: title) })
            }
        }
    }

    private func playable(_ ratingKey: String, title: String) async throws -> Playable {
        let playback = try await plex.playback(of: ratingKey)
        return Playable(title: title, url: playback.streamURL, startMilliseconds: playback.offset,
                        reportPosition: { await plex.reportProgress(of: ratingKey, milliseconds: $0) },
                        reportEnded: { await plex.scrobble(ratingKey) })
    }
}

/// Sort titles ignoring a leading "The", like title_sort_key in the old app.
func titleSortKey(_ title: String) -> String {
    let lower = title.lowercased()
    return lower.hasPrefix("the ") ? String(lower.dropFirst(4)) : lower
}
