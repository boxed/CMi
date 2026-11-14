import Foundation

/// Builds a menu. Re-run on refresh, so menus always show current data. Returning nil means there's
/// nothing to show any more (e.g. the last episode of a show was watched), and the navigator goes back.
typealias MenuSource = @MainActor () async throws -> Menu?

/// One screen of tiles: what one page of the old web frontend was.
struct Menu {
    var title: String?
    var layout: Layout
    /// Checked periodically while the menu is on screen. Returning true refreshes it.
    var poll: Poll?
    /// Menus that take typing, like search. The menu is refreshed after every change.
    var textInput: TextInput?

    enum Layout {
        /// The home screen: big square tiles with an icon (index.html, `.big_tiles`).
        case bigTiles(columns: Int, items: [MenuItem])
        /// Rows of cells (list.html and friends). Columns are as wide as their widest cell.
        case table([[Cell]])
    }

    struct TextInput {
        var insert: @MainActor (String) -> Void
        /// Returns false when there's nothing to delete.
        var deleteBackward: @MainActor () -> Bool
    }

    struct Poll {
        var interval: TimeInterval
        var check: @MainActor () async -> Bool

        /// Just refresh now and then, e.g. to pick up changes made elsewhere.
        static func refresh(every interval: TimeInterval) -> Poll {
            Poll(interval: interval) { true }
        }
    }
}

enum Cell {
    case tile(MenuItem)
    /// Non-interactive text, e.g. "Season 2". `size` defaults to the tile font size.
    case label(String, size: CGFloat? = nil)
    case empty
    /// Tiles in equal columns, as many as fit the width of the screen, wrapping into more rows. Alone in its
    /// row, and its columns don't line up with the table's, so a long list doesn't run off the side of the TV.
    case wrap([MenuItem])
}

struct MenuItem {
    var title: String
    var subtitle: String? = nil   // big tiles: second line ("3 new / 10 total")
    var extra: String? = nil      // table tiles: small trailing text
    var symbol: String? = nil     // big tiles: SF Symbol
    var unwatchedMarker = false   // the little bar on unwatched episodes
    var action: Action? = nil
    /// The right click menu.
    var contextActions: [ContextAction] = []

    struct ContextAction {
        var title: String
        var run: @MainActor () async -> Outcome
    }

    enum Action {
        /// Go one level deeper.
        case open(MenuSource)
        /// Start playback. The menu is refreshed when playback stops.
        case play(@MainActor () async throws -> Playable)
        /// Do something, then navigate.
        case run(@MainActor () async -> Outcome)
    }

    enum Outcome {
        case stay, refresh, back(levels: Int = 1)
    }

    /// Right click "Mark as watched", for episodes not watched yet.
    func markableAsWatched(_ watched: Bool, _ markWatched: @escaping @MainActor () async -> Void) -> MenuItem {
        guard !watched else { return self }
        var item = self
        item.contextActions.append(ContextAction(title: "Mark as watched") {
            await markWatched()
            return .refresh
        })
        return item
    }
}

extension Menu {
    /// One tile per row.
    static func list(_ title: String?, _ items: [MenuItem], poll: Poll? = nil) -> Menu {
        Menu(title: title, layout: .table(items.map { [.tile($0)] }), poll: poll)
    }

    /// Fills columns of `height` rows, left to right (tvshows/views.py index and plex/views.py to_columns).
    static func columns(_ title: String?, _ items: [MenuItem], height: Int = 11) -> Menu {
        let width = (items.count + height - 1) / height
        var rows = Array(repeating: Array(repeating: Cell.empty, count: width), count: min(height, items.count))
        for (i, item) in items.enumerated() {
            rows[i % height][i / height] = .tile(item)
        }
        return Menu(title: title, layout: .table(rows))
    }

    /// A message instead of tiles, e.g. errors.
    static func message(_ title: String, _ text: String) -> Menu {
        Menu(title: title, layout: .table([[.label(text)]]))
    }
}
