import AppKit
import MetalKit

/// MTKView that forwards keyboard and mouse input (cmi.js / grid_navigation.js keydown handlers).
final class TileView: MTKView {
    var center: MediaCenter?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let center else { return }
        switch event.keyCode {
        case 123: center.moveFocus(dx: -1, dy: 0)   // left
        case 124: center.moveFocus(dx: 1, dy: 0)    // right
        case 125: center.moveFocus(dx: 0, dy: 1)    // down
        case 126: center.moveFocus(dx: 0, dy: -1)   // up
        case 36, 76: center.go()                     // return, keypad enter
        case 53, 51: center.back()                   // escape, backspace
        default: super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        center?.click(at: CGPoint(x: p.x, y: bounds.height - p.y))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var renderer: Renderer!
    var center: MediaCenter!

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal is not supported") }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "CMi Metal Demo"
        window.center()

        let view = TileView(frame: window.contentLayoutRect, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.sampleCount = 4
        view.preferredFramesPerSecond = 120
        view.clearColor = MTLClearColor(red: 0.23, green: 0.06, blue: 0.28, alpha: 1)

        center = MediaCenter(device: device, scale: window.backingScaleFactor)
        renderer = Renderer(view: view)
        renderer.app = center
        view.center = center
        view.delegate = renderer

        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
        Snapshots.runIfRequested(renderer: renderer, center: center, view: view)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
