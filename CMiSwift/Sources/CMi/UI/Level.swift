import AppKit
import Metal

/// Layout constants from style2-retina.css, in CSS px. One CSS px is `zoom` points on screen.
enum Layout {
    /// The menus are drawn this much bigger than the old web frontend, to suit a TV across the room.
    /// Adjustable with e.g. `defaults write net.kodare.CMi zoom -float 1.25`.
    static let zoom: CGFloat = (UserDefaults.standard.object(forKey: "zoom") as? Double).map { CGFloat($0) } ?? 1.5

    static let tablesOrigin = CGPoint(x: 100, y: 60)     // .tiles { top: 60px; left: 100px }
    static let borderSpacing: CGFloat = 5                // .tiles { border-spacing: 5px }
    static let tilePadding = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10) // .tile { padding: 8px 10px }
    static let bigTileContent = CGSize(width: 200, height: 200) // .big_tiles td { width/height: 200px }
    static let tileFontSize: CGFloat = 15                // .tile { font-size: 15px }
    static let labelFontSize: CGFloat = 18               // .tiles .label { font-size: 18px }
    static let h1FontSize: CGFloat = 22                  // h1 { font-size: 22px; margin: 0 0 10px }
    static let headerOrigin = CGPoint(x: 105, y: 15)     // .header { left: 105px; top: 15px }
    static let headerFontSize: CGFloat = 35              // .header { font-size: 35px }
    static let scrollMargin: CGFloat = 60                // keep the focused tile this far from the edges
}

/// Colors from style2.css (all are left-to-right linear gradients).
enum Palette {
    static func rgb(_ hex: UInt32) -> SIMD4<Float> {
        SIMD4(Float((hex >> 16) & 0xff) / 255, Float((hex >> 8) & 0xff) / 255, Float(hex & 0xff) / 255, 1)
    }
    static let body = (rgb(0x3b1048), rgb(0x470e48))
    static let tile = (rgb(0x6b1d57), rgb(0x7d2764))
    static let focus = (rgb(0x23B4A9), rgb(0x188E86))
    static let pressed = (rgb(0x24dfd4), rgb(0x1cbdb5))
    static let marker = (rgb(0x24DFD4), rgb(0x24DFD4))   // .watched_marker div
}

/// A cell on screen: a focusable tile or a label. Both flip in and out.
struct Tile {
    var item: MenuItem?          // nil for labels
    var row: Int, column: Int
    var frame: CGRect            // un-transformed, unscrolled layout box (the <td>)
    var uv = SIMD4<Float>(repeating: 0)
    var transition = TileTransition.shown
    var pressed = false
    var pressChanged: CFTimeInterval = 0
}

/// One menu on screen: the `<h1 class="header">` plus the `<table class="tiles">`.
@MainActor
final class Level {
    let menu: Menu
    private(set) var tiles: [Tile] = []
    /// Indices into `tiles` of the focusable tiles, by row and column.
    private var grid: [[Int?]] = []
    private var tableFrame = CGRect.zero
    private var headerFrame = CGRect.zero
    private var headerUV = SIMD4<Float>(repeating: 0)
    /// The title turns with the page, as its first row.
    private var headerTransition = TileTransition.shown
    private(set) var texture: MTLTexture?

    /// Index into `tiles` of the focused tile, if any.
    var focus: Int?

    private var scroll = CGPoint.zero
    private var lastFrame: CFTimeInterval?

    init(menu: Menu, device: MTLDevice, scale: CGFloat) {
        self.menu = menu
        var atlas = AtlasBuilder()
        switch menu.layout {
        case .bigTiles(let columns, let items):
            layOutBigTiles(columns: columns, items: items, atlas: &atlas)
        case .table(let rows):
            layOutTable(rows, atlas: &atlas)
        }

        var headerIndex: Int?
        if let title = menu.title {
            let str = Fonts.attributed(title, Fonts.regular(Layout.headerFontSize))
            let size = CGSize(width: ceil(str.size().width) + 2, height: ceil(str.size().height))
            headerFrame = CGRect(origin: Layout.headerOrigin, size: size)
            headerIndex = atlas.add(size) { r in str.draw(at: r.origin) }
        }

        let (texture, uvs) = atlas.build(device: device, scale: scale)
        self.texture = texture
        for i in tiles.indices { tiles[i].uv = uvs[i] }
        if let headerIndex { headerUV = uvs[headerIndex] }
        focus = grid.joined().compactMap { $0 }.min()
    }

    // MARK: Layout

    private func layOutBigTiles(columns: Int, items: [MenuItem], atlas: inout AtlasBuilder) {
        let pad = Layout.tilePadding, s = Layout.borderSpacing, o = Layout.tablesOrigin
        let size = CGSize(width: Layout.bigTileContent.width + pad.left + pad.right,
                          height: Layout.bigTileContent.height + pad.top + pad.bottom)
        let rows = (items.count + columns - 1) / columns
        grid = Array(repeating: Array(repeating: nil, count: columns), count: rows)
        for (i, item) in items.enumerated() {
            let (row, column) = (i / columns, i % columns)
            let frame = CGRect(x: o.x + s + CGFloat(column) * (size.width + s),
                               y: o.y + s + CGFloat(row) * (size.height + s),
                               width: size.width, height: size.height)
            grid[row][column] = tiles.count
            tiles.append(Tile(item: item, row: row, column: column, frame: frame))
            atlas.add(size) { r in Level.drawBigTile(item, in: r) }
        }
        tableFrame = CGRect(x: o.x, y: o.y, width: CGFloat(columns) * (size.width + s) + s,
                            height: CGFloat(rows) * (size.height + s) + s)
    }

    /// HTML table auto layout: each column is as wide as its widest cell, each row as tall as its tallest.
    private func layOutTable(_ rows: [[Cell]], atlas: inout AtlasBuilder) {
        let pad = Layout.tilePadding, s = Layout.borderSpacing, o = Layout.tablesOrigin
        let columnCount = rows.map(\.count).max() ?? 0
        var widths = Array(repeating: CGFloat(0), count: columnCount)
        var heights = Array(repeating: CGFloat(0), count: rows.count)
        for (r, row) in rows.enumerated() {
            for (c, cell) in row.enumerated() {
                let size = Level.contentSize(of: cell)
                widths[c] = max(widths[c], size.width + pad.left + pad.right)
                heights[r] = max(heights[r], size.height + pad.top + pad.bottom)
            }
        }

        grid = Array(repeating: Array(repeating: nil, count: columnCount), count: rows.count)
        var y = o.y + s
        for (r, row) in rows.enumerated() {
            var x = o.x + s
            for (c, cell) in row.enumerated() {
                let frame = CGRect(x: x, y: y, width: widths[c], height: heights[r])
                x += widths[c] + s
                switch cell {
                case .empty:
                    continue
                case .tile(let item):
                    grid[r][c] = tiles.count
                    tiles.append(Tile(item: item, row: r, column: c, frame: frame))
                    atlas.add(frame.size) { rect in Level.drawTableTile(item, in: rect) }
                case .label(let text, let size):
                    tiles.append(Tile(item: nil, row: r, column: c, frame: frame))
                    let str = Fonts.attributed(text, Fonts.regular(size ?? Layout.labelFontSize))
                    atlas.add(frame.size) { rect in
                        str.draw(at: CGPoint(x: rect.minX + pad.left, y: rect.midY - str.size().height / 2))
                    }
                }
            }
            y += heights[r] + s
        }
        tableFrame = CGRect(x: o.x, y: o.y, width: widths.reduce(s) { $0 + $1 + s }, height: y - o.y)
    }

    private static func contentSize(of cell: Cell) -> CGSize {
        switch cell {
        case .empty:
            return .zero
        case .tile(let item):
            let (main, extra) = tableLabels(item)
            var width = main.size().width
            if let extra { width += Layout.tileFontSize * 3 + extra.size().width }   // .main_info { margin-right: 3em }
            if item.unwatchedMarker { width += 12 }
            return CGSize(width: ceil(width), height: Fonts.lineHeight(Fonts.regular(Layout.tileFontSize)))
        case .label(let text, let size):
            let font = Fonts.regular(size ?? Layout.labelFontSize)
            let str = Fonts.attributed(text, font)
            return CGSize(width: ceil(str.size().width), height: max(Fonts.lineHeight(font), ceil(str.size().height)))
        }
    }

    /// `<span class="main_info">` and the smaller `<span class="extra_info">` (font-size: 70%, float: right).
    private static func tableLabels(_ item: MenuItem) -> (NSAttributedString, NSAttributedString?) {
        let main = Fonts.attributed(item.title, Fonts.regular(Layout.tileFontSize))
        let extra = item.extra.map { Fonts.attributed($0, Fonts.regular(Layout.tileFontSize * 0.7)) }
        return (main, extra)
    }

    private static func drawTableTile(_ item: MenuItem, in r: CGRect) {
        let pad = Layout.tilePadding
        let (main, extra) = tableLabels(item)
        main.draw(at: CGPoint(x: r.minX + pad.left, y: r.midY - main.size().height / 2))
        var right = r.maxX - pad.right
        if item.unwatchedMarker {
            // .watched_marker div { width: 4px; height: 4px; background-color: #24DFD4; float: right }
            NSColor(red: 0x24 / 255, green: 0xDF / 255, blue: 0xD4 / 255, alpha: 1).setFill()
            CGRect(x: right - 4, y: r.midY - 2, width: 4, height: 4).fill()
            right -= 12
        }
        if let extra {
            extra.draw(at: CGPoint(x: right - extra.size().width, y: r.midY - extra.size().height / 2 + 1))
        }
    }

    /// tile.html: icon, then `<div class="content"><h1>title</h1>subtitle</div>`,
    /// bottom-aligned and centered (`.big_tile { vertical-align: bottom; text-align: center }`).
    private static func drawBigTile(_ item: MenuItem, in r: CGRect) {
        let pad = Layout.tilePadding
        let contentPadding: CGFloat = 22        // .content { padding: 22px 38px }
        var bottom = r.maxY - pad.bottom - contentPadding

        func centered(_ s: NSAttributedString, bottom: CGFloat) -> CGFloat {
            let size = s.size()
            s.draw(at: CGPoint(x: r.midX - size.width / 2, y: bottom - size.height))
            return bottom - size.height
        }
        if let sub = item.subtitle {
            bottom = centered(Fonts.attributed(sub, Fonts.regular(Layout.tileFontSize)), bottom: bottom) - 10
        }
        bottom = centered(Fonts.attributed(item.title, Fonts.regular(Layout.h1FontSize)), bottom: bottom)
        bottom -= contentPadding

        // .big_icon { width: 80px }
        if let name = item.symbol, let img = Fonts.symbol(name, pointSize: 52) {
            let box = CGSize(width: 80, height: 70)
            let k = min(box.width / img.size.width, box.height / img.size.height)
            let size = CGSize(width: img.size.width * k, height: img.size.height * k)
            img.draw(in: CGRect(x: r.midX - size.width / 2, y: bottom - size.height, width: size.width, height: size.height),
                     from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    // MARK: Focus

    var focusedItem: MenuItem? { focus.flatMap { tiles[$0].item } }

    /// Enough to find the focused tile again after the menu is rebuilt, even if tiles were added or removed.
    struct FocusMemory {
        var index: Int
        var title: String
    }

    var focusMemory: FocusMemory? {
        guard let focus, let item = tiles[focus].item else { return nil }
        return FocusMemory(index: focus, title: item.title)
    }

    /// Focuses the tile with the same title (the nearest one if several have it), else the same position.
    func restoreFocus(_ memory: FocusMemory) {
        let sameTitle = tiles.indices.filter { tiles[$0].item?.title == memory.title }
        if let nearest = sameTitle.min(by: { abs($0 - memory.index) < abs($1 - memory.index) }) {
            focus = nearest
        } else if memory.index < tiles.count, tiles[memory.index].item != nil {
            focus = memory.index
        }
    }

    /// grid_navigation.js: step in a direction to the next tile, skipping empty cells and labels.
    func moveFocus(dx: Int, dy: Int) {
        guard let focus else { return }
        var (row, column) = (tiles[focus].row + dy, tiles[focus].column + dx)
        while grid.indices.contains(row), grid[row].indices.contains(column) {
            if let i = grid[row][column] {
                self.focus = i
                return
            }
            (row, column) = (row + dy, column + dx)
        }
    }

    func setPressed(_ pressed: Bool, at i: Int) {
        guard tiles[i].pressed != pressed else { return }
        tiles[i].pressed = pressed
        tiles[i].pressChanged = CACurrentMediaTime()
    }

    func tileIndex(at p: CGPoint) -> Int? {
        let p = CGPoint(x: p.x + scroll.x, y: p.y + scroll.y)
        return tiles.firstIndex { $0.item != nil && $0.frame.contains(p) }
    }

    // MARK: Animation

    /// End time of the last running transition.
    var animationEnd: CFTimeInterval { max(headerTransition.end, tiles.map(\.transition.end).max() ?? 0) }

    /// Turnstile in, a row at a time after the title. Without `animated` (a refresh) the tiles just appear.
    func flipIn(at start: CFTimeInterval, direction: Motion.Direction, animated: Bool = true) {
        guard animated else {
            headerTransition = .shown
            for i in tiles.indices { tiles[i].transition = .shown }
            return
        }
        headerTransition = .entering(direction, start: start)
        for i in tiles.indices {
            tiles[i].transition = .entering(direction, start: start + Motion.inDelay(row: tiles[i].row + 1))
        }
    }

    /// Turnstile out, a row at a time, with the pressed tile (if any) last.
    func flipOut(now: CFTimeInterval, direction: Motion.Direction, pressed: Int? = nil) {
        headerTransition = headerTransition.exiting(direction, now: now, delay: 0)
        var lastDelay = 0.0
        for i in tiles.indices where i != pressed {
            let delay = Motion.outDelay(row: tiles[i].row + 1)
            tiles[i].transition = tiles[i].transition.exiting(direction, now: now, delay: delay)
            lastDelay = max(lastDelay, delay)
        }
        if let pressed {
            tiles[pressed].transition = tiles[pressed].transition.exiting(direction, now: now,
                                                                         delay: lastDelay + Motion.pressedLinger)
        }
    }

    /// How far a tile has sunk under a press.
    private func pressScale(_ tile: Tile, at now: CFTimeInterval) -> Float {
        let p = Float(Curve.easeOut((now - tile.pressChanged) / Motion.pressDuration))
        let sunk = tile.pressed ? p : 1 - p
        return 1 - (1 - Motion.pressedScale) * sunk
    }

    /// Scrolls (smoothly) so the focused tile stays on screen, like jquery.intoViewport did.
    private func updateScroll(now: CFTimeInterval, viewSize: CGSize) {
        var target = scroll
        if let focus {
            let f = tiles[focus].frame, m = Layout.scrollMargin
            if f.maxX - target.x > viewSize.width - m { target.x = f.maxX - viewSize.width + m }
            if f.minX - target.x < m { target.x = max(0, f.minX - m - Layout.tablesOrigin.x) }
            if f.maxY - target.y > viewSize.height - m { target.y = f.maxY - viewSize.height + m }
            if f.minY - target.y < m { target.y = max(0, f.minY - m - Layout.tablesOrigin.y) }
        }
        let dt = lastFrame.map { now - $0 } ?? 1
        lastFrame = now
        let k = CGFloat(min(1, dt * 12))
        scroll = CGPoint(x: scroll.x + (target.x - scroll.x) * k, y: scroll.y + (target.y - scroll.y) * k)
    }

    /// Instances for the renderer: the header, then each tile (and unwatched markers).
    func instances(at now: CFTimeInterval, viewSize: CGSize) -> [Instance] {
        updateScroll(now: now, viewSize: viewSize)
        var out: [Instance] = []
        let table = tableFrame.offsetBy(dx: -scroll.x, dy: -scroll.y)
        let po = SIMD2<Float>(Float(table.midX), Float(table.midY)) // perspective-origin: 50% 50%
        if menu.title != nil {
            let v = headerTransition.value(at: now)
            out.append(Instance(rect: headerFrame, uv: headerUV, colors: nil, opacity: v.opacity, angle: v.angle,
                                pivotX: 0, perspectiveOrigin: po, perspective: Motion.perspective))
        }
        for (i, t) in tiles.enumerated() {
            let v = t.transition.value(at: now)
            let colors = t.item == nil ? nil : t.pressed ? Palette.pressed : (i == focus ? Palette.focus : Palette.tile)
            // The pivot is the page's left edge (x = 0), so the whole page swings as one door
            out.append(Instance(rect: t.frame.offsetBy(dx: -scroll.x, dy: -scroll.y), uv: t.uv, colors: colors,
                                opacity: v.opacity, angle: v.angle, pivotX: 0, perspectiveOrigin: po,
                                perspective: Motion.perspective, scale: pressScale(t, at: now)))
        }
        return out
    }
}
