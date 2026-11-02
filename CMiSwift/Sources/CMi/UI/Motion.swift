import Foundation

/// Metro's turnstile page transition (Windows Phone): every tile hinges on the left edge of the screen and
/// swings like a revolving door, a row at a time. Going forward the old page swings away into the screen and
/// the new one swings in from the viewer's side; going back runs the door the other way.
enum Motion {
    enum Direction { case forward, back }

    static let inDuration = 0.35
    static let outDuration = 0.2

    /// Nearly edge-on, so tiles only swing a short way into place and never show their back.
    static let enterAngle: Float = 70 * .pi / 180
    static let exitAngle: Float = 90 * .pi / 180

    /// Positive angles swing a tile's right side away from the viewer.
    static func enteringAngle(_ direction: Direction) -> Float { direction == .forward ? -enterAngle : enterAngle }
    static func exitingAngle(_ direction: Direction) -> Float { direction == .forward ? exitAngle : -exitAngle }

    /// style2-retina.css: `.tiles { -webkit-perspective: 1900px; }`
    static let perspective: Float = 1900

    /// Rows move one after another, top first, with the stagger capped so long lists don't drag.
    /// Row 0 is the page title.
    static func inDelay(row: Int) -> Double { Double(min(max(row, 0), maxStaggeredRows)) * 0.03 }
    static func outDelay(row: Int) -> Double { Double(min(max(row, 0), maxStaggeredRows)) * 0.025 }
    private static let maxStaggeredRows = 8
    /// The pressed tile leaves this long after the last of the others, so the eye follows it to the next page.
    static let pressedLinger = 0.06
    /// The next page starts swinging in this long before the old one is completely gone.
    static let overlap = 0.12

    /// Press feedback: the tile sinks back a little.
    static let pressedScale: Float = 0.96
    static let pressDuration = 0.1

    /// How long focus rests on a tile before what it opens is loaded ahead, and how long that stays fresh.
    static let prefetchDelay = 0.15
    static let prefetchLifetime = 60.0

    /// `$('#back_link').animate({opacity: ...}, {duration: 300})`
    static let backButtonFade = 0.3
}

/// Metro's motion curves: exponential, fast and then settling (out), or gathering speed (in).
enum Curve {
    case easeOut, easeIn

    func callAsFunction(_ t: Double) -> Double {
        let t = max(0, min(1, t))
        switch self {
        case .easeOut: return (1 - exp(-6 * t)) / (1 - exp(-6))
        case .easeIn: return (exp(2 * t) - 1) / (exp(2) - 1)
        }
    }
}

/// A tile's rotateY angle and opacity, animating from one value to another after a delay.
struct TileTransition {
    var fromAngle: Float
    var toAngle: Float
    var fromOpacity: Float
    var toOpacity: Float
    var start: CFTimeInterval      // includes the delay
    var duration: CFTimeInterval
    var curve: Curve

    /// Showing, still.
    static let shown = TileTransition(fromAngle: 0, toAngle: 0, fromOpacity: 1, toOpacity: 1, start: 0, duration: 0, curve: .easeOut)

    var end: CFTimeInterval { start + duration }

    func value(at t: CFTimeInterval) -> (angle: Float, opacity: Float) {
        let p = duration > 0 ? Float(curve((t - start) / duration)) : 1
        return (fromAngle + (toAngle - fromAngle) * p,
                fromOpacity + (toOpacity - fromOpacity) * p)
    }

    /// Swinging in from edge-on, fading in as it comes.
    static func entering(_ direction: Motion.Direction, start: CFTimeInterval) -> TileTransition {
        TileTransition(fromAngle: Motion.enteringAngle(direction), toAngle: 0, fromOpacity: 0, toOpacity: 1,
                       start: start, duration: Motion.inDuration, curve: .easeOut)
    }

    /// Swinging out from wherever it is now, until edge-on.
    func exiting(_ direction: Motion.Direction, now: CFTimeInterval, delay: Double) -> TileTransition {
        let current = value(at: now)
        return TileTransition(fromAngle: current.angle, toAngle: Motion.exitingAngle(direction),
                              fromOpacity: current.opacity, toOpacity: current.opacity,
                              start: now + delay, duration: Motion.outDuration, curve: .easeIn)
    }
}

/// jQuery's default `swing` easing, used by `$('#back_link').animate({opacity: ...}, 300)`.
func swing(_ p: Double) -> Double {
    0.5 - cos(max(0, min(1, p)) * .pi) / 2
}
