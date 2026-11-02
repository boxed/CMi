import AppKit
import MediaPlayer
import MetalKit
import CMiCore
import CMiPlex
import CMiSVT

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var tileView: TileView!
    private var renderer: Renderer!
    private var navigator: Navigator!
    private var player: Player!
    private var overlay: ControlsOverlay!
    private var screen: Screen!
    private var library: Library!
    private var search: SearchMenus!
    private var isScanning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let paths = Paths.standard
        do {
            try FileManager.default.createDirectory(at: paths.supportFolder, withIntermediateDirectories: true)
            let database = try Database(url: paths.database)
            library = Library(paths: paths, database: database)
            let plex = Plex(store: PlexStore(supportFolder: paths.supportFolder))
            let local = LocalMenus(database: database, library: library)
            let plexMenus = PlexMenus(plex: plex, signIn: PlexSignIn(plex: plex))
            let svt = SVTMenus(svt: SVTPlay(), progress: SVTProgress(supportFolder: paths.supportFolder))
            search = SearchMenus(local: local, plex: plexMenus, svt: svt)
            let home = HomeMenu(local: local, plex: plexMenus, svt: svt, search: search)
            setUpWindow(home: { await home.menu() })
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "CMi couldn't open its database at \(paths.database.path)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        setUpMainMenu()
        setUpRemoteCommands()

        // Look for new downloads now and then, like the old search_for_new_files timer.
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
        scan()
        Snapshots.runIfRequested(renderer: renderer, view: tileView, player: player,
                                 press: { [weak self] in self?.press($0) }, type: { [weak self] in self?.type($0) },
                                 openSearch: { [weak self] in guard let self else { return }; navigator.open(search.source()) })
    }

    private func setUpWindow(home: @escaping MenuSource) {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal is not supported") }
        let windowed = ProcessInfo.processInfo.environment["CMI_WINDOWED"] != nil
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        if windowed {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.center()
        } else {
            // A media center owns the screen, like the old BorderLessWindow.
            window = KeyableWindow(contentRect: screenFrame, styleMask: [.borderless], backing: .buffered, defer: false)
            NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
        }
        window.title = "CMi"
        window.backgroundColor = .black

        let content = NSView(frame: window.contentLayoutRect)
        content.autoresizingMask = [.width, .height]

        player = Player()
        player.videoView.frame = content.bounds
        player.videoView.isHidden = true
        content.addSubview(player.videoView)

        tileView = TileView(frame: content.bounds, device: device)
        tileView.autoresizingMask = [.width, .height]
        tileView.colorPixelFormat = .bgra8Unorm
        tileView.sampleCount = 4
        tileView.preferredFramesPerSecond = 120
        tileView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        tileView.layer?.isOpaque = false   // the video shows through while playing
        content.addSubview(tileView)

        // Menu text and icons are drawn at the zoomed size, so they stay sharp
        navigator = Navigator(device: device, scale: window.backingScaleFactor * Layout.zoom, home: home)
        overlay = ControlsOverlay(player: player, device: device, scale: window.backingScaleFactor)
        screen = Screen(navigator: navigator, overlay: overlay, player: player)
        renderer = Renderer(view: tileView)
        renderer.source = screen
        tileView.delegate = renderer
        tileView.app = self

        navigator.onPlay = { [weak self] playable in self?.play(playable) }
        player.onStop = { [weak self] in self?.playbackStopped() }
        player.onResume = { [weak self] in self?.overlay.hide(force: true) }   // the controls are in the way of watching

        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(tileView)
        NSApp.activate()
    }

    // MARK: Playback

    private func play(_ playable: Playable) {
        overlay.hide(force: true)
        player.videoView.isHidden = false
        player.play(playable)
        updateNowPlaying()
    }

    private func playbackStopped() {
        overlay.hide(force: true)
        player.videoView.isHidden = true
        navigator.refresh()   // watched state and positions changed
        updateNowPlaying()
    }

    /// Without a main menu there's no ⌘Q, ⌘H etc. The menu bar itself is hidden while full screen,
    /// but the key equivalents still work.
    private func setUpMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About CMi", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide CMi", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit CMi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }

    private func setUpRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.playPause() }
            return .success
        }
        commands.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { if self?.player.isPaused == true { self?.player.playPause() } }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { if self?.player.isPaused == false { self?.player.playPause() } }
            return .success
        }
        commands.skipForwardCommand.preferredIntervals = [NSNumber(value: Player.jumpSeconds)]
        commands.skipForwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.jumpForward() }
            return .success
        }
        commands.skipBackwardCommand.preferredIntervals = [NSNumber(value: Player.jumpSeconds)]
        commands.skipBackwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.jumpBackward() }
            return .success
        }
    }

    /// Media keys only reach apps that say they're playing something.
    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        if let playable = player.playable {
            center.nowPlayingInfo = [MPMediaItemPropertyTitle: playable.title]
            center.playbackState = .playing
        } else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
        }
    }

    // MARK: Library

    private func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let changed = await library.scan()
            isScanning = false
            if changed && !player.isPlaying { navigator.refresh() }
        }
    }

    // MARK: Input

    enum Key: String {
        case left, right, up, down, enter, escape, backspace, space, m, r

        init?(_ event: NSEvent) {
            switch event.keyCode {
            case 123: self = .left
            case 124: self = .right
            case 125: self = .down
            case 126: self = .up
            case 36, 76: self = .enter      // return, keypad enter
            case 53: self = .escape
            case 51: self = .backspace
            case 49: self = .space
            case 46: self = .m
            case 15: self = .r
            default: return nil
            }
        }
    }

    func keyDown(_ event: NSEvent) {
        NSCursor.setHiddenUntilMouseMoves(true)
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        if !player.isPlaying {
            // ⌘F, or / when not already typing, searches from anywhere
            let character = event.charactersIgnoringModifiers?.lowercased()
            if (modifiers == .command && character == "f") || (modifiers.isEmpty && character == "/" && !navigator.acceptsText) {
                navigator.open(search.source())
                return
            }
            if navigator.acceptsText && modifiers.isEmpty {
                if event.keyCode == 51 {   // backspace deletes, and goes back once there's nothing left
                    if !navigator.deleteBackward() { navigator.back() }
                    return
                }
                if let text = event.characters, Self.isTypable(text) {
                    navigator.insertText(text)
                    return
                }
            }
        }
        guard modifiers.isEmpty, let key = Key(event) else { return }
        press(key)
    }

    /// Letters, digits, space and punctuation; not return, escape, arrows and other function keys.
    private static func isTypable(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar) && !(0xF700...0xF8FF).contains(scalar.value)
        }
    }

    /// Typing, for the snapshot self-test.
    func type(_ text: String) {
        navigator.insertText(text)
    }

    /// In menus: arrows move, return opens, escape/backspace go back, R refreshes.
    /// While playing (the old player's keys, plus left/right to skip like the remote had): space plays/pauses
    /// (or presses the focused control), return/escape/M show or hide the controls, left/right skip 30 seconds
    /// (or move between controls), up/down change the volume, backspace stops.
    func press(_ key: Key) {
        guard player.isPlaying else {
            switch key {
            case .left: navigator.moveFocus(dx: -1, dy: 0)
            case .right: navigator.moveFocus(dx: 1, dy: 0)
            case .down: navigator.moveFocus(dx: 0, dy: 1)
            case .up: navigator.moveFocus(dx: 0, dy: -1)
            case .enter: navigator.go()
            case .escape, .backspace: navigator.back()
            case .r: navigator.refresh()
            case .space, .m: break
            }
            return
        }
        switch (key, overlay.isShowing) {
        case (.space, true), (.enter, true): overlay.activate(overlay.focus)
        case (.space, false): player.playPause()
        case (.enter, false), (.escape, _), (.m, _): overlay.toggle()
        case (.left, true): overlay.moveFocus(by: -1)
        case (.right, true): overlay.moveFocus(by: 1)
        case (.left, false): player.jumpBackward()
        case (.right, false): player.jumpForward()
        case (.up, _): player.raiseVolume()
        case (.down, _): player.lowerVolume()
        case (.backspace, _): player.stop()
        case (.r, _): break
        }
    }

    /// `p` and `viewSize` are in view points, top left origin.
    func mouseDown(at p: CGPoint, viewSize: CGSize) {
        let z = screen.zoom
        let p = CGPoint(x: p.x / z, y: p.y / z)
        let viewSize = Renderer.layoutSize(of: viewSize, zoom: z)
        if player.isPlaying {
            if let button = overlay.button(at: p, viewSize: viewSize) {
                overlay.focus = button
                overlay.activate(button)
            } else {
                overlay.show(sticky: false)
            }
        } else {
            navigator.click(at: p)
        }
    }

    func mouseMoved() {
        if player.isPlaying { overlay.show(sticky: false) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        player?.stop()   // saves the position
    }
}

/// Menus, or the video with its controls on top.
@MainActor
final class Screen: FrameSource {
    let navigator: Navigator
    let overlay: ControlsOverlay
    let player: Player

    init(navigator: Navigator, overlay: ControlsOverlay, player: Player) {
        self.navigator = navigator
        self.overlay = overlay
        self.player = player
    }

    func frame(now: CFTimeInterval, viewSize: CGSize) -> [DrawBatch] {
        player.isPlaying ? overlay.frame(now: now, viewSize: viewSize) : navigator.frame(now: now, viewSize: viewSize)
    }

    var isIdle: Bool { player.isPlaying && overlay.isIdle }
    /// The menus are zoomed, the playback controls aren't.
    var zoom: CGFloat { player.isPlaying ? 1 : Layout.zoom }
}

/// Borderless windows can't become key by default, which they need to get keyboard input.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The Metal view, forwarding keyboard and mouse input to the app.
final class TileView: MTKView {
    weak var app: AppDelegate?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        app?.keyDown(event)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        app?.mouseDown(at: CGPoint(x: p.x, y: bounds.height - p.y), viewSize: bounds.size)
    }

    override func mouseMoved(with event: NSEvent) {
        app?.mouseMoved()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }
}
