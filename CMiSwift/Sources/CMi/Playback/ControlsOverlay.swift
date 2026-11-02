import AppKit
import Metal

/// What's drawn on top of the video: the on-screen controls (a row of Metro tiles with the title, time and
/// progress bar above), a pause indicator and the volume bar. The controls appear and disappear instantly.
@MainActor
final class ControlsOverlay: FrameSource {
    enum Button: Int, CaseIterable {
        case beginning, rewind, stop, playPause, forward, end

        func symbol(paused: Bool) -> String {
            switch self {
            case .beginning: "backward.end.fill"
            case .rewind: "gobackward.30"
            case .stop: "stop.fill"
            case .playPause: paused ? "play.fill" : "pause.fill"
            case .forward: "goforward.30"
            case .end: "forward.end.fill"
            }
        }
    }

    private let player: Player
    private let device: MTLDevice
    private let scale: CGFloat

    private(set) var isShowing = false
    /// Shown with the keyboard: stays until hidden again. Shown by moving the mouse: hides by itself.
    private var isSticky = false
    private var hideTask: Task<Void, Never>?
    var focus = Button.playPause

    private var iconTexture: MTLTexture?
    private var iconUVs: [String: SIMD4<Float>] = [:]
    private var textTexture: MTLTexture?
    private var text = ""
    private var textSize = CGSize.zero
    private var volumeShownAt: CFTimeInterval = -10
    private var lastVolume: Float

    static let tileSize = CGSize(width: 80, height: 80)
    static let opacity: Float = 0.85   // the old controls were translucent over the video too

    init(player: Player, device: MTLDevice, scale: CGFloat) {
        self.player = player
        self.device = device
        self.scale = scale
        lastVolume = player.volume
        buildIcons()
    }

    private func buildIcons() {
        var atlas = AtlasBuilder()
        var names: [String] = []
        for button in Button.allCases {
            for paused in [false, true] where !names.contains(button.symbol(paused: paused)) {
                let name = button.symbol(paused: paused)
                names.append(name)
                atlas.add(Self.tileSize) { r in
                    guard let image = Fonts.symbol(name, pointSize: 30) else { return }
                    let size = image.size
                    image.draw(in: CGRect(x: r.midX - size.width / 2, y: r.midY - size.height / 2, width: size.width, height: size.height),
                               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
            }
        }
        // The big pause indicator
        names.append("pause.big")
        atlas.add(CGSize(width: 160, height: 160)) { r in
            Fonts.symbol("pause.fill", pointSize: 70)?.draw(in: r.insetBy(dx: 40, dy: 35), from: .zero, operation: .sourceOver,
                                                          fraction: 1, respectFlipped: true, hints: nil)
        }
        let (texture, uvs) = atlas.build(device: device, scale: scale)
        iconTexture = texture
        iconUVs = Dictionary(uniqueKeysWithValues: zip(names, uvs))
    }

    // MARK: Showing and hiding

    func toggle() {
        if isShowing { hide(force: true) } else { show(sticky: true) }
    }

    func show(sticky: Bool) {
        hideTask?.cancel()
        isSticky = isSticky || sticky
        if !isShowing {
            isShowing = true
            focus = .playPause
        }
        if !isSticky {
            hideTask = Task {
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled { hide(force: false) }
            }
        }
    }

    func hide(force: Bool) {
        guard isShowing, force || !isSticky else { return }
        hideTask?.cancel()
        isShowing = false
        isSticky = false
        if player.isPlaying { NSCursor.setHiddenUntilMouseMoves(true) }   // moving the mouse shows both again
    }

    func moveFocus(by delta: Int) {
        focus = Button(rawValue: min(Button.allCases.count - 1, max(0, focus.rawValue + delta))) ?? focus
    }

    func activate(_ button: Button) {
        switch button {
        case .beginning: player.toBeginning()
        case .rewind: player.jumpBackward()
        case .stop: player.stop()
        case .playPause: player.playPause()
        case .forward: player.jumpForward()
        case .end: player.toEnd()
        }
    }

    func button(at p: CGPoint, viewSize: CGSize) -> Button? {
        guard isShowing else { return nil }
        return Button.allCases.first { frame(of: $0, viewSize: viewSize).contains(p) }
    }

    /// The fraction of the video at `p`, if it's on the progress bar (the hit area is taller than the bar).
    func progressFraction(at p: CGPoint, viewSize: CGSize) -> Double? {
        guard isShowing else { return nil }
        let bar = progressBarFrame(viewSize: viewSize)
        guard bar.insetBy(dx: 0, dy: -10).contains(p) else { return nil }
        return Double((p.x - bar.minX) / bar.width)
    }

    // MARK: Layout

    private func progressBarFrame(viewSize: CGSize) -> CGRect {
        let row = rowFrame(viewSize: viewSize)
        return CGRect(x: row.minX, y: row.minY - 20, width: row.width, height: 6)
    }

    private func rowFrame(viewSize: CGSize) -> CGRect {
        let s = Layout.borderSpacing
        let width = CGFloat(Button.allCases.count) * (Self.tileSize.width + s) - s
        return CGRect(x: (viewSize.width - width) / 2, y: viewSize.height - Self.tileSize.height - 60,
                      width: width, height: Self.tileSize.height)
    }

    private func frame(of button: Button, viewSize: CGSize) -> CGRect {
        let row = rowFrame(viewSize: viewSize)
        return CGRect(x: row.minX + CGFloat(button.rawValue) * (Self.tileSize.width + Layout.borderSpacing), y: row.minY,
                      width: Self.tileSize.width, height: Self.tileSize.height)
    }

    private static func format(_ milliseconds: Int) -> String {
        let s = max(0, milliseconds / 1000)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    private func updateText() {
        let title = player.playable?.title ?? ""
        let new = "\(title)    \(Self.format(player.currentTime)) / \(Self.format(player.duration))"
        guard new != text else { return }
        text = new
        let str = Fonts.attributed(text, Fonts.regular(Layout.labelFontSize))
        textSize = CGSize(width: ceil(str.size().width) + 2, height: ceil(str.size().height))
        var atlas = AtlasBuilder()
        atlas.add(textSize) { r in str.draw(at: r.origin) }
        textTexture = atlas.build(device: device, scale: scale).0
    }

    // MARK: Frame

    /// Nothing on screen: no controls, no pause indicator and no volume bar.
    var isIdle: Bool {
        !isShowing && !player.isPaused && player.volume == lastVolume && CACurrentMediaTime() - volumeShownAt > 1.5
    }

    func frame(now: CFTimeInterval, viewSize: CGSize) -> [DrawBatch] {
        var batches: [DrawBatch] = []
        let row = rowFrame(viewSize: viewSize)

        // Pause indicator, when the controls are out of the way.
        if player.isPaused && !isShowing, let uv = iconUVs["pause.big"] {
            let r = CGRect(x: (viewSize.width - 160) / 2, y: (viewSize.height - 160) / 2, width: 160, height: 160)
            batches.append(DrawBatch(texture: iconTexture, instances: [Instance(rect: r, uv: uv, colors: Palette.tile, opacity: Self.opacity)]))
        }

        if isShowing {
            updateText()
            // Progress bar and time, above the buttons.
            let bar = progressBarFrame(viewSize: viewSize)
            let progress = player.duration > 0 ? CGFloat(player.currentTime) / CGFloat(player.duration) : 0
            let buffered = player.bufferedUntil.map { CGFloat($0) / CGFloat(player.duration) } ?? 0
            batches.append(DrawBatch(texture: textTexture, instances: [
                Instance(rect: bar, uv: nil, colors: Palette.tile, opacity: Self.opacity),
                // What's downloaded ahead, dimmer than what's been played
                Instance(rect: CGRect(x: bar.minX, y: bar.minY, width: bar.width * min(1, buffered), height: bar.height),
                         uv: nil, colors: Palette.focus, opacity: Self.opacity * 0.35),
                Instance(rect: CGRect(x: bar.minX, y: bar.minY, width: bar.width * min(1, progress), height: bar.height),
                         uv: nil, colors: Palette.focus, opacity: Self.opacity),
                Instance(rect: CGRect(x: row.minX, y: bar.minY - 10 - textSize.height, width: textSize.width, height: textSize.height),
                         uv: SIMD4(0, 0, 1, 1), colors: nil, opacity: 1),
            ]))
            batches.append(DrawBatch(texture: iconTexture, instances: Button.allCases.map { button in
                Instance(rect: frame(of: button, viewSize: viewSize), uv: iconUVs[button.symbol(paused: player.isPaused)],
                         colors: button == focus ? Palette.focus : Palette.tile, opacity: Self.opacity)
            }))
        }

        // Volume bar on the right edge, for a moment after a change.
        if player.volume != lastVolume {
            lastVolume = player.volume
            volumeShownAt = now
        }
        let volumeOpacity = Float(max(0, min(1, 1.5 - (now - volumeShownAt))))
        if volumeOpacity > 0 {
            let track = CGRect(x: viewSize.width - 60, y: viewSize.height / 2 - 150, width: 20, height: 300)
            let level = track.height * CGFloat(player.volume)
            batches.append(DrawBatch(texture: nil, instances: [
                Instance(rect: track, uv: nil, colors: Palette.tile, opacity: volumeOpacity * Self.opacity),
                Instance(rect: CGRect(x: track.minX, y: track.maxY - level, width: track.width, height: level),
                         uv: nil, colors: Palette.focus, opacity: volumeOpacity),
            ]))
        }
        return batches
    }
}
