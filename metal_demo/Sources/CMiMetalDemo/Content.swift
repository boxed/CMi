import Foundation

/// One tile's content. `children` builds the next menu level (what the ajax
/// request for the tile's `url` would return in the real app).
struct MenuItem {
    var title: String
    var subtitle: String? = nil   // big tiles: second line ("105 new episodes")
    var extra: String? = nil      // list tiles: small trailing text ("2/2")
    var symbol: String? = nil     // SF Symbol standing in for the SVG icons
    var children: (() -> MenuSpec)? = nil
}

enum MenuStyle {
    case bigTiles(columns: Int)   // index.html, `.tiles.big_tiles`
    case list                     // list.html, `.list.tiles`, one tile per row
}

struct MenuSpec {
    var title: String?
    var style: MenuStyle
    var items: [MenuItem]
}

enum FakeData {
    static func home() -> MenuSpec {
        MenuSpec(title: nil, style: .bigTiles(columns: 3), items: [
            MenuItem(title: "TV Shows", subtitle: "105 new episodes", symbol: "tv", children: tvShows),
            MenuItem(title: "Movies", subtitle: "14 new / 14 total", symbol: "film", children: movies),
            MenuItem(title: "Plex", subtitle: "2 servers", symbol: "play.rectangle", children: plex),
            MenuItem(title: "Weather", subtitle: "11°, 39%", symbol: "cloud.sun", children: weather),
            MenuItem(title: "New TV Shows", subtitle: "1 new shows", symbol: "sparkles.tv", children: newShows),
            MenuItem(title: "Filesystem", symbol: "folder", children: { folder("/Volumes/Media") }),
        ])
    }

    static let shows: [(String, Int, Int)] = [
        ("Castle", 2, 2), ("Dexter", 9, 9), ("Futurama", 40, 102), ("Gilmore Girls", 1, 1),
        ("Glee", 19, 19), ("Grey's Anatomy", 1, 1), ("So You Think You Can Dance", 2, 2),
        ("The Big Bang Theory", 3, 3), ("The Colbert Report", 11, 11),
        ("The Daily Show With Jon Stewart", 10, 10), ("Top Gear", 7, 7), ("Doctor Who", 4, 13),
        ("Firefly", 0, 14), ("Fringe", 5, 22), ("Mad Men", 2, 13), ("Parks and Recreation", 6, 24),
        ("Breaking Bad", 1, 8), ("Community", 3, 25),
    ]

    static func tvShows() -> MenuSpec {
        MenuSpec(title: "TV Shows", style: .list, items: shows.map { name, new, total in
            MenuItem(title: name, extra: "\(new)/\(total)", children: { episodes(of: name, count: total) })
        })
    }

    static func episodes(of show: String, count: Int) -> MenuSpec {
        let n = min(count, 16)
        return MenuSpec(title: show, style: .list, items: (0..<n).map { i in
            MenuItem(title: "S01E\(String(format: "%02d", i + 1))", extra: i < 2 ? "new" : "watched")
        })
    }

    static func movies() -> MenuSpec {
        let titles = ["Alien", "Blade Runner", "Brazil", "Contact", "Gattaca", "Heat", "Inception",
                      "Moon", "Primer", "Sunshine", "The Matrix", "Up", "WALL·E", "Zodiac"]
        return MenuSpec(title: "Movies", style: .list, items: titles.map { MenuItem(title: $0, extra: "new") })
    }

    static func plex() -> MenuSpec {
        MenuSpec(title: "Plex", style: .list, items: [
            MenuItem(title: "Living room server", extra: "3 libraries", children: {
                MenuSpec(title: "Living room server", style: .list, items: [
                    MenuItem(title: "Movies", extra: "212"), MenuItem(title: "TV Shows", extra: "48"),
                    MenuItem(title: "Music", extra: "1 024"),
                ])
            }),
            MenuItem(title: "NAS", extra: "1 library", children: {
                MenuSpec(title: "NAS", style: .list, items: [MenuItem(title: "Home videos", extra: "87")])
            }),
        ])
    }

    static func weather() -> MenuSpec {
        let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        return MenuSpec(title: "Weather", style: .list, items: days.enumerated().map { i, d in
            MenuItem(title: d, extra: "\(8 + i % 4)°, \(30 + i * 5)%")
        })
    }

    static func newShows() -> MenuSpec {
        MenuSpec(title: "New TV Shows", style: .list, items: [
            MenuItem(title: "Orphan Black", extra: "1 episode"),
        ])
    }

    static func folder(_ path: String) -> MenuSpec {
        let names = ["Downloads", "Movies", "TV", "Music", "Incoming", "Old stuff"]
        let depth = path.split(separator: "/").count
        return MenuSpec(title: path, style: .list, items: names.map { name in
            MenuItem(title: name, extra: "folder",
                     children: depth < 5 ? { folder(path + "/" + name) } : nil)
        })
    }
}
