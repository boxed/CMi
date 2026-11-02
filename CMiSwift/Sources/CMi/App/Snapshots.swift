import AppKit
import MetalKit

/// Opt-in self-test: with `CMI_SNAPSHOT_DIR=some/dir`, the app presses the keys in `CMI_SNAPSHOT_PATH`
/// (comma separated `AppDelegate.Key` names like "enter,down,enter,escape", plus "wait" for 5 seconds,
/// "video" to save the current video frame, "search" to open search, "type:some text" to type, and
/// "film:enter" to press a key and save a frame every 50 ms for a second, to check animations ("film:still"
/// just films)),
/// writes an offscreen render as a PNG after each step, then quits.
/// Handy where screen capture isn't allowed.
@MainActor
enum Snapshots {
    static func runIfRequested(renderer: Renderer, view: MTKView, player: Player, press: @escaping (AppDelegate.Key) -> Void,
                               type: @escaping (String) -> Void, openSearch: @escaping () -> Void) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["CMI_SNAPSHOT_DIR"] else { return }
        let folder = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let steps = (env["CMI_SNAPSHOT_PATH"] ?? "enter,escape").split(separator: ",").map(String.init)

        func shot(_ name: String) {
            renderer.snapshot(size: view.bounds.size, scale: view.window?.backingScaleFactor ?? 2,
                              to: folder.appendingPathComponent(name + ".png"))
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            shot("0_start")
            for (i, step) in steps.enumerated() {
                let name = "\(i + 1)_\(step.replacing(":", with: "_").replacing(" ", with: "_"))"
                if step.hasPrefix("film:") {
                    let what = String(step.dropFirst(5))
                    if what != "still" {   // "film:still" films without pressing anything
                        guard let key = AppDelegate.Key(rawValue: what) else { fatalError("Unknown snapshot step \(step)") }
                        press(key)
                    }
                    for frame in 0..<20 {
                        shot("\(name)_\(String(format: "%02d", frame))")
                        try? await Task.sleep(for: .seconds(0.05))
                    }
                    try? await Task.sleep(for: .seconds(1.5))
                    shot(name)
                    continue
                }
                if step.hasPrefix("type:") {
                    type(String(step.dropFirst(5)))
                    try? await Task.sleep(for: .seconds(0.3))
                    shot(name)
                    continue
                }
                switch step {
                case "search":
                    openSearch()
                    try? await Task.sleep(for: .seconds(2.5))
                case "wait":
                    try? await Task.sleep(for: .seconds(5))
                case "video":
                    // Asking VLC for a frame with nothing playing stalled the self-test
                    if player.isPlaying {
                        player.saveVideoFrame(to: folder.appendingPathComponent(name + "_video.png"))
                    }
                    try? await Task.sleep(for: .seconds(1))
                default:
                    guard let key = AppDelegate.Key(rawValue: step) else { fatalError("Unknown snapshot step \(step)") }
                    press(key)
                    try? await Task.sleep(for: .seconds(key == .enter || key == .escape || key == .backspace ? 2.5 : 0.4))
                }
                shot(name)
            }
            NSApp.terminate(nil)
        }
    }
}
