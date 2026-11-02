import AppKit
import Metal

/// The menu navigation state machine, mirroring go() / back() / refresh() / flip_in() / flip_out() in cmi.js.
@MainActor
final class Navigator: FrameSource {
    private let device: MTLDevice
    private let scale: CGFloat

    /// Called for `.play` tiles. The navigator refreshes when told playback stopped.
    var onPlay: ((Playable) -> Void)?

    private var current: Level?
    private var currentSource: MenuSource
    private var leaving: [Level] = []
    /// menu_history + menu_history_position: the levels below this one and their focus.
    private var history: [(source: MenuSource, focus: Level.FocusMemory?)] = []
    /// Bumped on every navigation, so a slow load can't replace a newer screen.
    private var generation = 0
    private var pollTask: Task<Void, Never>?

    private var chrome: Chrome

    init(device: MTLDevice, scale: CGFloat, home: @escaping MenuSource) {
        self.device = device
        self.scale = scale
        currentSource = home
        chrome = Chrome(device: device, scale: scale)
        load(home, focus: nil, direction: .forward)
    }

    // MARK: Input

    func moveFocus(dx: Int, dy: Int) {
        current?.moveFocus(dx: dx, dy: dy)
    }

    func click(at p: CGPoint) {
        if Chrome.backButtonFrame.contains(p) { back(); return }  // #back_link onclick
        guard let level = current, let i = level.tileIndex(at: p) else { return }
        level.focus = i
        go()
    }

    /// cmi.js go(): mark the tile `.pressed`, then open, play or run it.
    func go() {
        guard let level = current, let i = level.focus, let item = level.focusedItem, let action = item.action else { return }
        level.setPressed(true, at: i)
        switch action {
        case .open(let source):
            history.append((currentSource, level.focusMemory))
            navigate(to: source, focus: nil, direction: .forward, pressed: i)
        case .play(let makePlayable):
            Task {
                defer { level.setPressed(false, at: i) }
                do {
                    onPlay?(try await makePlayable())
                } catch {
                    show(.message("Couldn't play \(item.title)", error.localizedDescription), focus: nil, direction: .forward)
                }
            }
        case .run(let run):
            Task {
                let outcome = await run()
                level.setPressed(false, at: i)
                switch outcome {
                case .stay: break
                case .refresh: refresh()
                case .back(let levels): back(levels: levels)
                }
            }
        }
    }

    /// cmi.js back(): turnstile the current level out backwards, then the previous one in with its focus restored.
    func back(levels: Int = 1) {
        guard !history.isEmpty else { return }
        var previous = history.removeLast()
        for _ in 1..<max(1, levels) where !history.isEmpty {
            previous = history.removeLast()
        }
        navigate(to: previous.source, focus: previous.focus, direction: .back)
    }

    /// Rebuilds the current menu in place, without animation (cmi.js refresh()).
    func refresh() {
        load(currentSource, focus: current?.focusMemory, direction: nil)
    }

    var isAtHome: Bool { history.isEmpty }

    /// Opens a menu on top of the current one, like pressing a tile that opens it.
    func open(_ source: @escaping MenuSource) {
        if current != nil {
            history.append((currentSource, current?.focusMemory))
        }
        navigate(to: source, focus: nil, direction: .forward)
    }

    // MARK: Typing

    var acceptsText: Bool { current?.menu.textInput != nil }

    func insertText(_ text: String) {
        guard let input = current?.menu.textInput else { return }
        input.insert(text)
        refresh()
    }

    /// Returns false when there was nothing to delete.
    func deleteBackward() -> Bool {
        guard let input = current?.menu.textInput, input.deleteBackward() else { return false }
        refresh()
        return true
    }

    // MARK: Loading

    private func navigate(to source: @escaping MenuSource, focus: Level.FocusMemory?, direction: Motion.Direction,
                          pressed: Int? = nil) {
        if let level = current {
            level.flipOut(now: CACurrentMediaTime(), direction: direction, pressed: pressed)
            leaving.append(level)
            current = nil
        }
        currentSource = source
        load(source, focus: focus, direction: direction)
    }

    /// A nil direction (a refresh) shows the menu without animation.
    private func load(_ source: @escaping MenuSource, focus: Level.FocusMemory?, direction: Motion.Direction?) {
        generation += 1
        let generation = generation
        pollTask?.cancel()
        Task {
            let menu: Menu?
            do {
                menu = try await source()
            } catch {
                menu = .message("Something went wrong", error.localizedDescription)
            }
            guard generation == self.generation else { return }
            guard let menu else {
                back()   // nothing left here, e.g. the last episode was watched
                return
            }
            show(menu, focus: focus, direction: direction)
        }
    }

    private func show(_ menu: Menu, focus: Level.FocusMemory?, direction: Motion.Direction?) {
        let level = Level(menu: menu, device: device, scale: scale)
        if let focus {
            level.restoreFocus(focus)
        }
        // The new page swings in as the old one finishes swinging out
        let now = CACurrentMediaTime()
        let outgoing = leaving.map(\.animationEnd).max() ?? 0
        level.flipIn(at: max(now, outgoing - Motion.overlap), direction: direction ?? .forward, animated: direction != nil)
        current = level
        chrome.setBackButtonVisible(!history.isEmpty)
        startPolling(menu.poll)
    }

    private func startPolling(_ poll: Menu.Poll?) {
        pollTask?.cancel()
        guard let poll else { return }
        let generation = generation
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(poll.interval))
                guard !Task.isCancelled, generation == self.generation else { return }
                if await poll.check() {
                    refresh()
                    return
                }
            }
        }
    }

    // MARK: Frame

    /// Draw order: body background, the incoming level, then the outgoing levels on top
    /// (flip_out() raises the old container to z-index 100, new ones get 0), then chrome.
    func frame(now: CFTimeInterval, viewSize: CGSize) -> [DrawBatch] {
        leaving.removeAll { now > $0.animationEnd + 0.05 }
        var batches = [chrome.background(viewSize: viewSize)]
        if let current {
            batches.append(DrawBatch(texture: current.texture, instances: current.instances(at: now, viewSize: viewSize)))
        }
        for level in leaving {
            batches.append(DrawBatch(texture: level.texture, instances: level.instances(at: now, viewSize: viewSize)))
        }
        batches.append(chrome.foreground(now: now, viewSize: viewSize))
        return batches
    }
}

/// The page background, `#clock` and `#back_link`.
@MainActor
struct Chrome {
    static let backButtonFrame = CGRect(x: 5, y: 5, width: 30, height: 30)   // #back_link { top: 5px; left: 5px }

    private let device: MTLDevice
    private let scale: CGFloat
    private var texture: MTLTexture?
    private var clockText = ""
    private var clockUV = SIMD4<Float>(repeating: 0)
    private var clockSize = CGSize.zero
    private var backUV = SIMD4<Float>(repeating: 0)
    private var backOpacity = (from: 0.0, to: 0.0, start: 0.0)

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f
    }()

    init(device: MTLDevice, scale: CGFloat) {
        self.device = device
        self.scale = scale
        rebuild()
    }

    private mutating func rebuild() {
        clockText = Chrome.clockFormatter.string(from: Date())
        let clock = Fonts.attributed(clockText, Fonts.regular(20))   // #clock { font-size: 20px }
        clockSize = CGSize(width: ceil(clock.size().width) + 2, height: ceil(clock.size().height))

        var atlas = AtlasBuilder()
        atlas.add(clockSize) { r in clock.draw(at: r.origin) }
        atlas.add(Chrome.backButtonFrame.size) { r in
            Fonts.symbol("arrow.left.circle", pointSize: 26)?
                .draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let (tex, uvs) = atlas.build(device: device, scale: scale)
        texture = tex
        clockUV = uvs[0]
        backUV = uvs[1]
    }

    /// show_hide_back_button(): `$('#back_link').animate({opacity: 0|1}, {duration: 300})`
    mutating func setBackButtonVisible(_ visible: Bool) {
        let now = CACurrentMediaTime()
        backOpacity = (from: backOpacityValue(now), to: visible ? 1 : 0, start: now)
    }

    private func backOpacityValue(_ now: CFTimeInterval) -> Double {
        let p = swing((now - backOpacity.start) / Motion.backButtonFade)
        return backOpacity.from + (backOpacity.to - backOpacity.from) * p
    }

    func background(viewSize: CGSize) -> DrawBatch {
        DrawBatch(texture: texture, instances: [
            Instance(rect: CGRect(origin: .zero, size: viewSize), uv: nil, colors: Palette.body, opacity: 1),
        ])
    }

    mutating func foreground(now: CFTimeInterval, viewSize: CGSize) -> DrawBatch {
        if Chrome.clockFormatter.string(from: Date()) != clockText { rebuild() }
        // #clock { top: 3px; right: 5px }
        let clockRect = CGRect(x: viewSize.width - 5 - clockSize.width, y: 3, width: clockSize.width, height: clockSize.height)
        return DrawBatch(texture: texture, instances: [
            Instance(rect: clockRect, uv: clockUV, colors: nil, opacity: 1),
            Instance(rect: Chrome.backButtonFrame, uv: backUV, colors: nil, opacity: Float(backOpacityValue(now))),
        ])
    }
}
