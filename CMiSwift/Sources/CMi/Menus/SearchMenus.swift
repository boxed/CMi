import Foundation

/// Searching every source at once: local TV shows and movies, Plex and SVT Play.
@MainActor
struct SearchMenus {
    let local: LocalMenus
    let plex: PlexMenus
    let svt: SVTMenus

    func tile() -> MenuItem {
        MenuItem(title: "Search", symbol: "magnifyingglass", action: .open(source()))
    }

    /// A search screen with its own query, which survives the screen being refreshed.
    func source() -> MenuSource {
        let model = SearchModel(search: results)
        return { menu(model) }
    }

    private func menu(_ model: SearchModel) -> Menu {
        let builtVersion = model.version
        var menu: Menu
        if model.query.isEmpty {
            menu = .message("Search", "Type to search TV shows, movies, Plex and SVT Play")
        } else if let results = model.results {
            let columns = results.filter { !$0.items.isEmpty }
            menu = columns.isEmpty && model.resultsQuery == model.query
                ? .message("", "Nothing found")
                : columnGrid(title: "", columns: columns, next: nil)
        } else {
            menu = .message("", "Searching…")
        }
        menu.title = "Search: \(model.query)_"
        menu.textInput = Menu.TextInput(insert: model.insert, deleteBackward: model.deleteBackward)
        // Refresh when results for a newer query arrive
        menu.poll = Menu.Poll(interval: 0.2) { model.version != builtVersion }
        return menu
    }

    /// All sources at once. A source that fails gets a note instead of its results.
    private func results(_ query: String) async -> [(label: String, items: [MenuItem])] {
        let localResults = local.search(query)
        async let plexResults = attempt { try await plex.search(query) }
        async let svtResults = attempt { try await svt.search(query) }
        return [
            ("TV Shows", localResults.shows),
            ("Movies", localResults.movies),
            ("Plex", await plexResults),
            ("SVT Play", await svtResults),
        ]
    }

    private func attempt(_ search: @MainActor () async throws -> [MenuItem]) async -> [MenuItem] {
        do {
            return try await search()
        } catch {
            return [MenuItem(title: "Couldn't search", extra: error.localizedDescription)]
        }
    }
}

/// The query being typed, and the results for it. Searches run when typing pauses.
@MainActor
final class SearchModel {
    private(set) var query = ""
    /// The latest results, which may be for an earlier query while a new search runs.
    private(set) var results: [(label: String, items: [MenuItem])]?
    private(set) var resultsQuery = ""
    /// Bumped whenever new results arrive.
    private(set) var version = 0

    private let search: @MainActor (String) async -> [(label: String, items: [MenuItem])]
    private var task: Task<Void, Never>?

    init(search: @escaping @MainActor (String) async -> [(label: String, items: [MenuItem])]) {
        self.search = search
    }

    func insert(_ text: String) {
        query += text
        searchSoon()
    }

    func deleteBackward() -> Bool {
        guard !query.isEmpty else { return false }
        query.removeLast()
        searchSoon()
        return true
    }

    private func searchSoon() {
        task?.cancel()
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            results = nil
            return
        }
        task = Task {
            try? await Task.sleep(for: .seconds(0.4))
            guard !Task.isCancelled else { return }
            let found = await search(query)
            guard !Task.isCancelled else { return }
            results = found
            resultsQuery = query
            version += 1
        }
    }
}
