import AppKit
import Metal

/// Layout constants from style2-retina.css (CSS px == macOS points).
enum Layout {
    static let tablesOrigin = CGPoint(x: 100, y: 60)     // .tiles { top: 60px; left: 100px }
    static let borderSpacing: CGFloat = 5                // .tiles { border-spacing: 5px }
    static let tilePadding = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10) // .tile { padding: 8px 10px }
    static let bigTileContent = CGSize(width: 200, height: 200) // .big_tiles td { width/height: 200px }
    static let tileFontSize: CGFloat = 15                // .tile { font-size: 15px }
    static let h1FontSize: CGFloat = 22                  // h1 { font-size: 22px; margin: 0 0 10px }
    static let headerOrigin = CGPoint(x: 105, y: 15)     // .header { left: 105px; top: 15px }
    static let headerFontSize: CGFloat = 35              // .header { font-size: 35px }
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
}

struct Tile {
    var item: MenuItem
    var frame: CGRect          // un-transformed layout box (the <td>)
    var uv = SIMD4<Float>(repeating: 0)
    var transition = TileTransition.resting()
    var pressed = false
}

/// One menu level: the `<h1 class="header">` plus the `<table class="tiles">`.
final class Level {
    let spec: MenuSpec
    let columns: Int
    var tiles: [Tile] = []
    var tableFrame = CGRect.zero
    var headerFrame = CGRect.zero
    var headerUV = SIMD4<Float>(repeating: 0)
    var headerVisible = false
    var focus = 0
    var texture: MTLTexture!

    init(spec: MenuSpec, device: MTLDevice, scale: CGFloat) {
        self.spec = spec
        var atlas = AtlasBuilder()
        let font = Fonts.regular(Layout.tileFontSize)
        let pad = Layout.tilePadding
        let s = Layout.borderSpacing
        let o = Layout.tablesOrigin

        switch spec.style {
        case .bigTiles(let cols):
            columns = cols
            let size = CGSize(width: Layout.bigTileContent.width + pad.left + pad.right,
                              height: Layout.bigTileContent.height + pad.top + pad.bottom)
            for (i, item) in spec.items.enumerated() {
                let (row, col) = (i / cols, i % cols)
                let frame = CGRect(x: o.x + s + CGFloat(col) * (size.width + s),
                                   y: o.y + s + CGFloat(row) * (size.height + s),
                                   width: size.width, height: size.height)
                tiles.append(Tile(item: item, frame: frame))
                atlas.add(size) { r in Level.drawBigTile(item, in: r) }
            }
            let rows = (spec.items.count + cols - 1) / cols
            tableFrame = CGRect(x: o.x, y: o.y,
                                width: CGFloat(cols) * (size.width + s) + s,
                                height: CGFloat(rows) * (size.height + s) + s)

        case .list:
            columns = 1
            let small = Fonts.regular(Layout.tileFontSize * 0.7)
            let contentWidth = spec.items.map { Level.listLabel($0, font, small).size().width }.max() ?? 0
            let size = CGSize(width: ceil(contentWidth) + pad.left + pad.right,
                              height: Fonts.lineHeight(font) + pad.top + pad.bottom)
            for (i, item) in spec.items.enumerated() {
                let frame = CGRect(x: o.x + s, y: o.y + s + CGFloat(i) * (size.height + s),
                                   width: size.width, height: size.height)
                tiles.append(Tile(item: item, frame: frame))
                atlas.add(size) { r in
                    let label = Level.listLabel(item, font, small)
                    label.draw(at: CGPoint(x: r.minX + pad.left, y: r.midY - label.size().height / 2))
                }
            }
            tableFrame = CGRect(x: o.x, y: o.y, width: size.width + 2 * s,
                                height: CGFloat(spec.items.count) * (size.height + s) + s)
        }

        var headerIndex: Int?
        if let title = spec.title {
            let str = Fonts.attributed(title, Fonts.regular(Layout.headerFontSize))
            let size = CGSize(width: ceil(str.size().width) + 2, height: ceil(str.size().height))
            headerFrame = CGRect(origin: Layout.headerOrigin, size: size)
            headerIndex = atlas.add(size) { r in str.draw(at: r.origin) }
        }

        let (tex, uvs) = atlas.build(device: device, scale: scale)
        texture = tex
        for i in tiles.indices { tiles[i].uv = uvs[i] }
        if let h = headerIndex { headerUV = uvs[h] }
    }

    /// `<span class="main_info">` followed by the smaller `<span class="extra_info">` (font-size: 70%).
    static func listLabel(_ item: MenuItem, _ font: NSFont, _ small: NSFont) -> NSAttributedString {
        let s = NSMutableAttributedString(attributedString: Fonts.attributed(item.title, font))
        if let extra = item.extra {
            s.append(Fonts.attributed(" " + extra, small))
        }
        return s
    }

    /// tile.html: icon, then `<div class="content"><h1>title</h1>subtitle</div>`,
    /// bottom-aligned and centered (`.big_tile { vertical-align: bottom; text-align: center }`).
    static func drawBigTile(_ item: MenuItem, in r: CGRect) {
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

    var rows: Int { (tiles.count + columns - 1) / columns }

    /// grid_navigation.js set_focus(): move one step, stop at the edges.
    func moveFocus(dx: Int, dy: Int) {
        let x = focus % columns + dx, y = focus / columns + dy
        guard x >= 0, x < columns, y >= 0, y < rows else { return }
        let i = y * columns + x
        if i < tiles.count { focus = i }
    }

    /// End time of the last running transition.
    var animationEnd: CFTimeInterval { tiles.map(\.transition.end).max() ?? 0 }

    /// cmi.js flip_in(): tiles transition from rotateY(150deg)/opacity 0 to
    /// rotateY(0)/opacity 1, each delayed by its `.started .flip_N` delay.
    func flipIn(now: CFTimeInterval) {
        headerVisible = true
        for i in tiles.indices {
            tiles[i].transition.retarget(angle: 0, opacity: 1, now: now, delay: CMi.flipInDelay(i))
        }
    }

    /// cmi.js flip_out(): tiles transition to rotateY(-90deg), opacity untouched,
    /// delayed by min(i, 10) * 50ms. The header is hidden immediately.
    func flipOut(now: CFTimeInterval) {
        headerVisible = false
        for i in tiles.indices {
            let current = tiles[i].transition.value(at: now)
            tiles[i].transition.retarget(angle: CMi.flipOutAngle, opacity: current.opacity, now: now,
                                         delay: CMi.flipOutDelay(i))
        }
    }

    func tileIndex(at p: CGPoint) -> Int? {
        tiles.firstIndex { $0.frame.contains(p) }
    }

    /// Instances for the renderer: the header, then each tile.
    func instances(at now: CFTimeInterval) -> [Instance] {
        var out: [Instance] = []
        if spec.title != nil && headerVisible {
            out.append(Instance(rect: headerFrame, uv: headerUV, colors: nil, opacity: 1))
        }
        let po = SIMD2<Float>(Float(tableFrame.midX), Float(tableFrame.midY)) // perspective-origin: 50% 50%
        for (i, t) in tiles.enumerated() {
            let v = t.transition.value(at: now)
            let colors = t.pressed ? Palette.pressed : (i == focus ? Palette.focus : Palette.tile)
            // transform-origin-x = -(offset().left): the pivot is the page's left edge (x = 0).
            out.append(Instance(rect: t.frame, uv: t.uv, colors: colors, opacity: v.opacity,
                                angle: v.angle, pivotX: 0, perspectiveOrigin: po, perspective: CMi.perspective))
        }
        return out
    }
}
