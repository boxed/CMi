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
    /// menu_history + menu_history_position: the levels below this one, their focus, and what they showed,
    /// so going back is instant.
    private var history: [(source: MenuSource, focus: Level.FocusMemory?, menu: Menu?)] = []
    /// Bumped on every navigation, so a slow load can't replace a newer screen.
    private var generation = 0
    private var pollTask: Task<Void, Never>?
    /// The menu behind the focused tile, loaded while the user decides, so opening it doesn't wait on the network.
    private var prefetch: (level: Level, tile: Int, started: CFTimeInterval, task: Task<Menu?, Error>)?
    private var prefetchDelay: Task<Void, Never>?

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
        prefetchSoon()
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
            history.append((currentSource, level.focusMemory, level.menu))
            navigate(to: source, focus: nil, direction: .forward, pressed: i, loaded: prefetched(level, i))
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
        let loaded = previous.menu.map { menu in Task<Menu?, Error> { menu } }
        navigate(to: previous.source, focus: previous.focus, direction: .back, loaded: loaded)
        // What it showed might be out of date by now
        if loaded != nil {
            refreshAfterAnimation = true
        }
    }

    /// Rebuilds the current menu in place, without animation (cmi.js refresh()).
    func refresh() {
        load(currentSource, focus: current?.focusMemory, direction: nil)
    }

    var isAtHome: Bool { history.isEmpty }

    /// Opens a menu on top of the current one, like pressing a tile that opens it.
    func open(_ source: @escaping MenuSource) {
        if current != nil {
            history.append((currentSource, current?.focusMemory, current?.menu))
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

    // MARK: Type to jump

    /// What's been typed to jump to a tile, like in Finder lists. Forgotten after a pause in typing.
    private var typeAhead = ""
    private var typeAheadAt: CFTimeInterval = 0

    /// Returns false when the key wasn't used, so a space that doesn't continue a prefix can do its usual thing.
    func typeToJump(_ text: String) -> Bool {
        guard let level = current else { return false }
        let now = CACurrentMediaTime()
        if now - typeAheadAt > 1 { typeAhead = "" }
        if typeAhead.isEmpty && text.allSatisfy(\.isWhitespace) { return false }
        typeAheadAt = now
        typeAhead += text
        if level.focusFirst(withPrefix: typeAhead) {
            prefetchSoon()
        }
        return true
    }

    // MARK: Loading

    /// `loaded` is the menu if it's already loaded (or loading).
    private func navigate(to source: @escaping MenuSource, focus: Level.FocusMemory?, direction: Motion.Direction,
                          pressed: Int? = nil, loaded: Task<Menu?, Error>? = nil) {
        if let level = current {
            level.flipOut(now: CACurrentMediaTime(), direction: direction, pressed: pressed)
            leaving.append(level)
            current = nil
        }
        currentSource = source
        load(source, focus: focus, direction: direction, loaded: loaded)
    }

    /// A nil direction (a refresh) shows the menu without animation.
    private func load(_ source: @escaping MenuSource, focus: Level.FocusMemory?, direction: Motion.Direction?,
                      loaded: Task<Menu?, Error>? = nil) {
        generation += 1
        let generation = generation
        pollTask?.cancel()
        prefetchDelay?.cancel()
        if let unused = prefetch?.task, unused != loaded {
            unused.cancel()
        }
        prefetch = nil
        Task {
            let menu: Menu?
            do {
                menu = try await (loaded ?? Task { try await source() }).value
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
        if refreshAfterAnimation {
            refreshAfterAnimation = false
            let generation = generation
            Task {
                try? await Task.sleep(for: .seconds(max(0, level.animationEnd - CACurrentMediaTime())))
                if generation == self.generation { refresh() }
            }
        }
        prefetchSoon()
    }

    /// Set when going back to a remembered menu, to reload it once it has swung in.
    private var refreshAfterAnimation = false

    /// Starts loading what the focused tile opens, once focus has rested on it for a moment.
    private func prefetchSoon() {
        prefetchDelay?.cancel()
        guard let level = current, let i = level.focus, case .open(let source)? = level.focusedItem?.action,
              prefetch?.level !== level || prefetch?.tile != i else { return }
        prefetchDelay = Task {
            try? await Task.sleep(for: .seconds(Motion.prefetchDelay))
            guard !Task.isCancelled, current === level, level.focus == i else { return }
            prefetch?.task.cancel()
            prefetch = (level, i, CACurrentMediaTime(), Task { try await source() })
        }
    }

    /// The prefetched menu for a tile, unless it's too old to trust.
    private func prefetched(_ level: Level, _ i: Int) -> Task<Menu?, Error>? {
        guard let prefetch, prefetch.level === level, prefetch.tile == i,
              CACurrentMediaTime() - prefetch.started < Motion.prefetchLifetime else { return nil }
        return prefetch.task
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
