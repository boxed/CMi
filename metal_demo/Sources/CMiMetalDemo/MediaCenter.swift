import AppKit
import Metal

/// The navigation state machine, mirroring go() / back() / flip_in() / flip_out() in cmi.js.
final class MediaCenter {
    let device: MTLDevice
    let scale: CGFloat

    private(set) var current: Level?
    private var leaving: [Level] = []
    /// menu_history + menu_history_position: the specs of the levels below this one and their focus.
    private var history: [(spec: MenuSpec, focus: Int)] = []
    private var started = false

    // #back_link and #clock
    private var chromeTexture: MTLTexture!
    private var clockText = ""
    private var clockUV = SIMD4<Float>(repeating: 0)
    private var clockSize = CGSize.zero
    private var backUV = SIMD4<Float>(repeating: 0)
    private var backOpacity = (from: 0.0, to: 0.0, start: 0.0)

    init(device: MTLDevice, scale: CGFloat) {
        self.device = device
        self.scale = scale
        current = Level(spec: FakeData.home(), device: device, scale: scale)
        rebuildChrome()
    }

    // MARK: Input

    func moveFocus(dx: Int, dy: Int) {
        current?.moveFocus(dx: dx, dy: dy)
    }

    func click(at p: CGPoint) {
        if CGRect(x: 5, y: 5, width: 30, height: 30).contains(p) { back(); return }  // #back_link onclick
        guard let level = current, let i = level.tileIndex(at: p) else { return }
        level.focus = i
        go()
    }

    /// cmi.js go(): mark the tile `.pressed`, flip_out(), "fetch" the next level and flip_in() it.
    func go() {
        guard let level = current, level.tiles.indices.contains(level.focus) else { return }
        let i = level.focus
        level.tiles[i].pressed = true
        guard let children = level.tiles[i].item.children else {
            // A leaf (an episode or movie): the real app would start playback.
            DispatchQueue.main.asyncAfter(deadline: .now() + CMi.transitionDuration) {
                level.tiles[i].pressed = false
            }
            return
        }
        history.append((level.spec, i))
        flipOutCurrent()
        DispatchQueue.main.asyncAfter(deadline: .now() + CMi.simulatedServerLatency) { [self] in
            show(children(), focus: 0)
        }
    }

    /// cmi.js back(): flip_out() the current level, then flip_in() the previous one
    /// with the focus restored. (The original uses the same animation both ways.)
    func back() {
        guard current != nil, let previous = history.popLast() else { return }
        flipOutCurrent()
        DispatchQueue.main.asyncAfter(deadline: .now() + CMi.simulatedServerLatency) { [self] in
            show(previous.spec, focus: previous.focus)
        }
    }

    private func flipOutCurrent() {
        guard let level = current else { return }
        level.flipOut(now: CACurrentMediaTime())
        leaving.append(level)
        current = nil
    }

    private func show(_ spec: MenuSpec, focus: Int) {
        let level = Level(spec: spec, device: device, scale: scale)
        level.focus = focus
        level.flipIn(now: CACurrentMediaTime())
        current = level
        animateBackButton(visible: !history.isEmpty)
    }

    /// show_hide_back_button(): `$('#back_link').animate({opacity: 0|1}, {duration: 300})`
    private func animateBackButton(visible: Bool) {
        let now = CACurrentMediaTime()
        backOpacity = (from: backOpacityValue(now), to: visible ? 1 : 0, start: now)
    }

    private func backOpacityValue(_ now: CFTimeInterval) -> Double {
        let p = swing((now - backOpacity.start) / CMi.transitionDuration)
        return backOpacity.from + (backOpacity.to - backOpacity.from) * p
    }

    // MARK: Chrome

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f
    }()

    private func rebuildChrome() {
        clockText = MediaCenter.clockFormatter.string(from: Date())
        let clock = Fonts.attributed(clockText, Fonts.regular(20))   // #clock { font-size: 20px }
        clockSize = CGSize(width: ceil(clock.size().width) + 2, height: ceil(clock.size().height))

        var atlas = AtlasBuilder()
        atlas.add(clockSize) { r in clock.draw(at: r.origin) }
        atlas.add(CGSize(width: 30, height: 30)) { r in              // #back_link { 30px x 30px }
            Fonts.symbol("arrow.left.circle", pointSize: 26)?
                .draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let (tex, uvs) = atlas.build(device: device, scale: scale)
        chromeTexture = tex
        clockUV = uvs[0]
        backUV = uvs[1]
    }

    // MARK: Frame

    /// Draw order: body background, the incoming level, then the outgoing levels on top
    /// (flip_out() raises the old container to z-index 100, new ones get 0), then chrome.
    func frame(now: CFTimeInterval, viewSize: CGSize) -> [DrawBatch] {
        if !started {
            // $(document).ready(): flip_in('table') on load. Start once the window is up.
            started = true
            current?.flipIn(now: now + 0.15)
        }
        leaving.removeAll { now > $0.animationEnd + 0.05 }

        if MediaCenter.clockFormatter.string(from: Date()) != clockText { rebuildChrome() }

        var batches: [DrawBatch] = []
        let full = CGRect(origin: .zero, size: viewSize)
        batches.append(DrawBatch(texture: chromeTexture,
                                 instances: [Instance(rect: full, uv: nil, colors: Palette.body, opacity: 1)]))
        if let current { batches.append(DrawBatch(texture: current.texture, instances: current.instances(at: now))) }
        for level in leaving { batches.append(DrawBatch(texture: level.texture, instances: level.instances(at: now))) }

        // #clock { top: 3px; right: 5px }, #back_link { top: 5px; left: 5px }
        let clockRect = CGRect(x: viewSize.width - 5 - clockSize.width, y: 3, width: clockSize.width, height: clockSize.height)
        batches.append(DrawBatch(texture: chromeTexture, instances: [
            Instance(rect: clockRect, uv: clockUV, colors: nil, opacity: 1),
            Instance(rect: CGRect(x: 5, y: 5, width: 30, height: 30), uv: backUV, colors: nil,
                     opacity: Float(backOpacityValue(now))),
        ]))
        return batches
    }
}
