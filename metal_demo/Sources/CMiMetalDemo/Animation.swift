import Foundation

/// Constants and formulas ported from the CMi web frontend.
enum CMi {
    /// cmi.js: `var transitionDuration = 300;`
    static let transitionDuration = 0.300

    /// style2.css: `.tiles td { -webkit-transform: translate3d(0,0,0) rotateY(150deg); }`
    static let restingAngle: Float = 150 * .pi / 180
    /// cmi.js flip_out(): `rotateY(-90deg)`
    static let flipOutAngle: Float = -90 * .pi / 180

    /// style2-retina.css: `.tiles { -webkit-perspective: 1900px; }`
    static let perspective: Float = 1900

    /// views.py css(): `.started .flip_N {-webkit-transition-delay: max(40, N * (40 - N//2))ms}`
    static func flipInDelay(_ i: Int) -> Double {
        let delay = 40
        return Double(max(delay, i * (delay - i / 2))) / 1000
    }

    /// cmi.js flip_out(): `webkitTransitionDelay: Math.min(_i, 10) * 50 + "ms"`
    static func flipOutDelay(_ i: Int) -> Double {
        Double(min(i, 10) * 50) / 1000
    }

    /// Simulated time for the ajax round trip between flip_out() and flip_in().
    static let simulatedServerLatency = 0.030
}

/// CSS `ease` timing function, i.e. cubic-bezier(0.25, 0.1, 0.25, 1.0).
/// No transition-timing-function is set on the tiles, so WebKit uses the default `ease`.
struct CubicBezier {
    let x1: Double, y1: Double, x2: Double, y2: Double
    static let ease = CubicBezier(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1.0)

    private func sample(_ t: Double, _ a1: Double, _ a2: Double) -> Double {
        // B(t) = 3(1-t)^2 t a1 + 3(1-t) t^2 a2 + t^3
        let u = 1 - t
        return 3 * u * u * t * a1 + 3 * u * t * t * a2 + t * t * t
    }

    private func sampleDerivativeX(_ t: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * x1 + 6 * u * t * (x2 - x1) + 3 * t * t * (1 - x2)
    }

    func callAsFunction(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        // Newton-Raphson, falling back to bisection (same approach as WebKit's UnitBezier).
        var t = x
        for _ in 0..<8 {
            let err = sample(t, x1, x2) - x
            if abs(err) < 1e-6 { return sample(t, y1, y2) }
            let d = sampleDerivativeX(t)
            if abs(d) < 1e-6 { break }
            t -= err / d
        }
        var lo = 0.0, hi = 1.0
        t = x
        while hi - lo > 1e-7 {
            let v = sample(t, x1, x2)
            if v < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return sample(t, y1, y2)
    }
}

/// A CSS-transition-like animation of a tile's rotateY angle and opacity.
/// Like a CSS transition, the "from" value is whatever the tile showed when the
/// target changed, and the value is held during the delay.
struct TileTransition {
    var fromAngle: Float
    var toAngle: Float
    var fromOpacity: Float
    var toOpacity: Float
    var start: CFTimeInterval      // includes the transition delay
    var duration: CFTimeInterval = CMi.transitionDuration

    static func resting() -> TileTransition {
        TileTransition(fromAngle: CMi.restingAngle, toAngle: CMi.restingAngle,
                       fromOpacity: 0, toOpacity: 0, start: 0)
    }

    var end: CFTimeInterval { start + duration }

    func value(at t: CFTimeInterval) -> (angle: Float, opacity: Float) {
        let p = Float(CubicBezier.ease(max(0, min(1, (t - start) / duration))))
        return (fromAngle + (toAngle - fromAngle) * p,
                fromOpacity + (toOpacity - fromOpacity) * p)
    }

    /// Retarget from the current value, like changing a transitioned CSS property.
    mutating func retarget(angle: Float, opacity: Float, now: CFTimeInterval, delay: Double) {
        let current = value(at: now)
        self = TileTransition(fromAngle: current.angle, toAngle: angle,
                              fromOpacity: current.opacity, toOpacity: opacity,
                              start: now + delay)
    }
}

/// jQuery's default `swing` easing, used by `$('#back_link').animate({opacity: ...}, 300)`.
func swing(_ p: Double) -> Double {
    0.5 - cos(max(0, min(1, p)) * .pi) / 2
}
