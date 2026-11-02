import Foundation
import CMiCore

/// The home screen: TV shows (and a tile per category), movies, Plex, SVT Play and search.
@MainActor
struct HomeMenu {
    let local: LocalMenus
    let plex: PlexMenus
    let svt: SVTMenus
    let search: SearchMenus

    func menu() async -> Menu {
        var items = [local.tvShowsTile(category: nil)]
        items += local.database.categories().map { local.tvShowsTile(category: $0) }
        items.append(local.moviesTile())
        items.append(await plex.tile())
        items.append(svt.tile())
        items.append(search.tile())
        return Menu(title: nil, layout: .bigTiles(columns: 3, items: items))
    }
}
