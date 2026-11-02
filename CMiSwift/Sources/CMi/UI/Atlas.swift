import AppKit
import Metal

/// Builds a texture atlas by drawing each entry with AppKit/Core Text into one bitmap (entries packed in
/// rows), then uploading it to Metal. Entries are drawn white-on-transparent; the shader composites them over
/// the tile background gradient.
@MainActor
struct AtlasBuilder {
    struct Entry {
        var size: CGSize                       // in points
        var draw: (CGRect) -> Void             // draws into a flipped (y-down) context
    }

    var entries: [Entry] = []

    /// Metal's texture size limit on Apple GPUs.
    static let maxTextureSide = 16384

    /// Returns the index of the entry, used to look up its UV rect after `build`.
    @discardableResult
    mutating func add(_ size: CGSize, draw: @escaping (CGRect) -> Void) -> Int {
        entries.append(Entry(size: size, draw: draw))
        return entries.count - 1
    }

    /// Places the entries left to right in rows no wider than `width` points. Returns their rects and the height.
    private func pack(width: CGFloat, gap: CGFloat) -> ([CGRect], CGFloat) {
        var rects: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for e in entries {
            if x > 0 && x + e.size.width > width {
                (x, y, rowHeight) = (0, y + rowHeight + gap, 0)
            }
            rects.append(CGRect(origin: CGPoint(x: x, y: y), size: e.size))
            x += e.size.width + gap
            rowHeight = max(rowHeight, e.size.height)
        }
        return (rects, y + rowHeight)
    }

    /// Returns the texture and a UV rect (u0, v0, u1, v1) per entry.
    func build(device: MTLDevice, scale requestedScale: CGFloat) -> (MTLTexture, [SIMD4<Float>]) {
        let gap: CGFloat = 2
        let maxSide = CGFloat(Self.maxTextureSide)
        // Aim for a roughly square texture, at least as wide as the widest entry.
        let area = entries.reduce(0) { $0 + ($1.size.width + gap) * ($1.size.height + gap) }
        let widest = entries.map(\.size.width).max() ?? 1
        let widthPt = max(1, min(max(widest, area.squareRoot()), maxSide / requestedScale))
        let (rects, packedHeight) = pack(width: widthPt, gap: gap)
        let heightPt = max(1, packedHeight)
        // Huge menus: draw at a lower resolution rather than exceed the texture limit.
        let scale = min(requestedScale, maxSide / max(widthPt, heightPt))
        let w = min(Self.maxTextureSide, Int((widthPt * scale).rounded(.up)))
        let h = min(Self.maxTextureSide, Int((heightPt * scale).rounded(.up)))

        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // y-down coordinates in points, so row 0 of the bitmap is v = 0 in Metal.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        var uvs: [SIMD4<Float>] = []
        for (e, r) in zip(entries, rects) {
            ctx.saveGState()
            ctx.clip(to: r)
            e.draw(r)
            ctx.restoreGState()
            uvs.append(SIMD4(Float(r.minX * scale / CGFloat(w)),
                             Float(r.minY * scale / CGFloat(h)),
                             Float(r.maxX * scale / CGFloat(w)),
                             Float(r.maxY * scale / CGFloat(h))))
        }
        NSGraphicsContext.restoreGraphicsState()

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = .shaderRead
        let tex = device.makeTexture(descriptor: desc)!
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                    withBytes: ctx.data!, bytesPerRow: w * 4)
        return (tex, uvs)
    }
}

// MARK: - Typography (style2.css / style2-retina.css)

@MainActor
enum Fonts {
    /// `font-family: century gothic, segoe ui, verdana, arial, sans-serif`.
    /// Century Gothic ships with MS Office, not macOS; Avenir Next is the closest
    /// geometric sans that comes with the system.
    static func regular(_ size: CGFloat) -> NSFont {
        NSFont(name: "CenturyGothic", size: size)
            ?? NSFont(name: "AvenirNext-Regular", size: size)
            ?? NSFont(name: "Verdana", size: size)
            ?? .systemFont(ofSize: size)
    }

    static func lineHeight(_ font: NSFont) -> CGFloat {
        // Approximates CSS `line-height: normal` (~1.2em). Avenir's own metrics are much taller.
        ceil(font.pointSize * 1.2)
    }

    static func attributed(_ s: String, _ font: NSFont) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor.white])
    }

    static func symbol(_ name: String, pointSize: CGFloat) -> NSImage? {
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        return img.withSymbolConfiguration(config)
    }
}
