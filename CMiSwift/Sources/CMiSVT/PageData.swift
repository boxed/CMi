import Foundation

/// svtplay.se renders its pages from GraphQL responses that it also embeds in the HTML as
/// `URQL_DATA = {"<query id>": {"data": "<JSON string>"}, …}`. Reading those is far more stable than scraping
/// the markup, and it's how svtplay-dl does it too. Only the parts CMi uses are decoded, all leniently.
struct PageData: Decodable {
    var startForSvtPlay: StartPageDTO?
    var detailsPageByPath: DetailsPageDTO?
    var programAtillO: AllProgramsDTO?
    var searchPage: SearchPageDTO?

    /// Merges the data of every embedded query on the page.
    static func parse(html: String) throws -> PageData {
        guard let start = html.range(of: "URQL_DATA = ") else { throw SVTError.unexpectedPage }
        let rest = html[start.upperBound...]
        guard let end = rest.range(of: "</script>") else { throw SVTError.unexpectedPage }
        var json = rest[..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasSuffix(";") { json.removeLast() }

        struct Entry: Decodable { var data: String? }
        let entries = try JSONDecoder().decode([String: Entry].self, from: Data(json.utf8))
        var page = PageData()
        for data in entries.values.compactMap(\.data) {
            guard let part = try? JSONDecoder().decode(PageData.self, from: Data(data.utf8)) else { continue }
            page.startForSvtPlay = page.startForSvtPlay ?? part.startForSvtPlay
            page.detailsPageByPath = page.detailsPageByPath ?? part.detailsPageByPath
            page.programAtillO = page.programAtillO ?? part.programAtillO
            page.searchPage = page.searchPage ?? part.searchPage
        }
        return page
    }

    private init() {}
}

struct StartPageDTO: Decodable {
    struct Modules: Decodable { var items: [ModuleDTO]? }
    var modules: Modules?
}

struct DetailsPageDTO: Decodable {
    struct Item: Decodable { var name: String? }
    var heading: String?
    var item: Item?
    var modules: [ModuleDTO]?
}

struct AllProgramsDTO: Decodable {
    var selections: [SelectionDTO]?
}

struct SearchPageDTO: Decodable {
    struct Flat: Decodable { var hits: [Hit]? }
    /// Category hits ("categoryTeaser") have no teaser and are skipped
    struct Hit: Decodable { var teaser: TeaserDTO? }
    var flat: Flat?

    var teasers: [SVTTeaser] {
        (flat?.hits ?? []).compactMap { hit in
            guard var teaser = hit.teaser?.teaser else { return nil }
            // Matches are wrapped in <em>. Episodes are "Program" with the episode in the subheading.
            teaser.title = teaser.title.withoutTags
            let episode = teaser.subtitle?.withoutTags ?? ""
            if case .video = teaser.kind, !episode.isEmpty, episode != teaser.title {
                teaser.title += " – " + episode
            }
            teaser.subtitle = nil
            return teaser
        }
    }
}

extension String {
    var withoutTags: String { replacing(/<[^>]*>/, with: "") }
}

/// A module holds at most one selection, under a key that depends on how it's presented
/// ("defaultSelection", "toplistSelection", "portraitSelection", …).
struct ModuleDTO: Decodable {
    var id: String?
    var selection: SelectionDTO?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = try? c.decodeIfPresent(String.self, forKey: AnyKey("id"))
        selection = c.allKeys
            .filter { $0.stringValue == "selection" || $0.stringValue.hasSuffix("Selection") }
            .lazy.compactMap { try? c.decodeIfPresent(SelectionDTO.self, forKey: $0) }
            .first
    }
}

struct SelectionDTO: Decodable {
    var name: String?
    var selectionType: String?
    var items: [TeaserDTO]?
    /// Program pages list their episodes here
    var itemsAdult: [TeaserDTO]?

    var teasers: [SVTTeaser] { (itemsAdult ?? items ?? []).compactMap(\.teaser) }
}

struct TeaserDTO: Decodable {
    struct Item: Decodable {
        struct URLs: Decodable { var svtplay: String? }
        var urls: URLs?
    }
    var heading: String?
    var subHeading: String?
    var item: Item?

    var teaser: SVTTeaser? {
        guard let path = item?.urls?.svtplay, let heading, !heading.isEmpty else { return nil }
        return SVTTeaser(path: path, title: heading, subtitle: subHeading)
    }
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// api.svt.se/video/<id>
struct VideoDTO: Decodable {
    struct Rights: Decodable { var drmCopyProtection: Bool? }
    struct Reference: Decodable {
        var format: String?
        var url: String?
    }
    var programTitle: String?
    var episodeTitle: String?
    var rights: Rights?
    var videoReferences: [Reference]?
}
