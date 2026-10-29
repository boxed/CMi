import AppKit
import MetalKit

/// Opt-in self-test: `CMI_SNAPSHOT_DIR=some/dir swift run` drives a short scripted
/// navigation and writes offscreen renders as PNGs, then quits. Useful where
/// `screencapture` isn't permitted.
enum Snapshots {
    static func runIfRequested(renderer: Renderer, center: MediaCenter, view: MTKView) {
        guard let dir = ProcessInfo.processInfo.environment["CMI_SNAPSHOT_DIR"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let script: [(Double, () -> Void)] = [
            (0.25, { shot("1_home_flip_in") }),
            (1.2, { shot("2_home") }),
            (1.3, { center.moveFocus(dx: 1, dy: 0); center.moveFocus(dx: -1, dy: 0) }),
            (1.4, { center.go() }),
            (1.55, { shot("3_transition") }),
            (1.75, { shot("4_transition") }),
            (2.6, { center.moveFocus(dx: 0, dy: 1) }),
            (2.7, { shot("5_tv_shows") }),
            (2.8, { center.back() }),
            (2.95, { shot("6_back") }),
            (4.0, { NSApp.terminate(nil) }),
        ]
        for (t, action) in script {
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: action)
        }
        func shot(_ name: String) {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name + ".png")
            renderer.snapshot(size: view.bounds.size, scale: view.window?.backingScaleFactor ?? 2, to: url)
        }
    }
}

extension Renderer {
    /// Renders one frame offscreen (same pipeline, MSAA resolved) and writes it as a PNG.
    func snapshot(size: CGSize, scale: CGFloat, to url: URL) {
        guard let app else { return }
        let w = Int(size.width * scale), h = Int(size.height * scale)
        let msaaDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        msaaDesc.textureType = .type2DMultisample
        msaaDesc.sampleCount = 4
        msaaDesc.usage = .renderTarget
        msaaDesc.storageMode = .private
        let resolveDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        resolveDesc.usage = [.renderTarget, .shaderRead]
        resolveDesc.storageMode = .managed
        guard let msaa = device.makeTexture(descriptor: msaaDesc),
              let resolved = device.makeTexture(descriptor: resolveDesc),
              let cmd = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = msaa
        pass.colorAttachments[0].resolveTexture = resolved
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .multisampleResolve
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        encode(app.frame(now: CACurrentMediaTime(), viewSize: size), viewSize: size, into: enc)
        enc.endEncoding()
        let blit = cmd.makeBlitCommandEncoder()!
        blit.synchronize(resource: resolved)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        resolved.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info),
              let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
