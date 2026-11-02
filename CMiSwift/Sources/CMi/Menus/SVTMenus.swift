import Foundation
import CMiSVT

/// SVT Play: the start page's lists, all programs A–Ö, and continuing what you're in the middle of.
@MainActor
struct SVTMenus {
    let svt: SVTPlay
    let progress: SVTProgress

    func tile() -> MenuItem {
        MenuItem(title: "SVT Play", symbol: "play.tv", action: .open { try await root() })
    }

    /// What you're in the middle of as one row on top, then the start page's lists and A–Ö.
    func root() async throws -> Menu {
        var rows: [[Cell]] = []
        let continuing = await progress.inProgress()
        if !continuing.isEmpty {
            rows.append([.label("Continue watching")])
            rows.append(continuing.map { entry in
                .tile(MenuItem(title: entry.title, action: .play { try await playable(entry.videoID) }))
            })
            rows.append([.empty])
        }
        let sections = try await svt.startPage()
        rows += sections.map { section in
            [.tile(MenuItem(title: section.name, extra: String(section.items.count), action: .open { await list(section) }))]
        }
        rows.append([.tile(MenuItem(title: "Program A–Ö", action: .open { try await letters() }))])
        return Menu(title: "SVT Play", layout: .table(rows))
    }

    private func list(_ section: SVTSection) async -> Menu {
        .columns(section.name, await section.items.asyncMap(item))
    }

    private func letters() async throws -> Menu {
        let letters = try await svt.allPrograms().map { letter in
            MenuItem(title: letter.name, extra: String(letter.items.count), action: .open { await list(letter) })
        }
        return .columns("Program A–Ö", letters, height: 10)
    }

    /// A video plays, a program opens its page.
    private func item(_ teaser: SVTTeaser) async -> MenuItem {
        switch teaser.kind {
        case .video(let id):
            let watched = await progress.entry(for: id)?.watched ?? false
            return MenuItem(title: teaser.title, unwatchedMarker: !watched, action: .play { try await playable(id) })
        case .program(let path):
            return MenuItem(title: teaser.title, action: .open { try await program(path) })
        }
    }

    /// One column per season, with the next episode to watch on top.
    private func program(_ path: String) async throws -> Menu {
        let program = try await svt.program(path)
        guard !program.seasons.isEmpty else { return .message(program.title, "Nothing to watch right now") }
        var columns: [(label: String, items: [MenuItem])] = []
        for season in program.seasons {
            columns.append((season.name, await season.items.asyncMap(item)))
        }
        let next = await progress.nextEpisode(in: program.seasons.flatMap(\.items))
        var nextItem: MenuItem?
        if let next {
            nextItem = await item(next)
            nextItem?.title = "Next: " + next.title
        }
        return columnGrid(title: program.title, columns: columns, next: nextItem)
    }

    /// Programs and videos from SVT Play's own search.
    func search(_ query: String) async throws -> [MenuItem] {
        try await svt.search(query).asyncMap(item)
    }

    private func playable(_ videoID: String) async throws -> Playable {
        let stream = try await svt.stream(for: videoID)
        let entry = await progress.entry(for: videoID)
        return Playable(title: stream.title, url: stream.url,
                        startMilliseconds: entry.map { $0.watched ? 0 : $0.milliseconds } ?? 0,
                        reportPosition: { await progress.setPosition(of: videoID, title: stream.title, milliseconds: $0) },
                        reportEnded: { await progress.markWatched(videoID, title: stream.title) },
                        keepsSubtitles: true)
    }
}

extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        for element in self {
            result.append(try await transform(element))
        }
        return result
    }
}
