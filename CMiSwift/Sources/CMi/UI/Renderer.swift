import MetalKit

/// Per-instance data for one quad. Layout matches `Instance` in the shader
/// (seven float4s, 112 bytes).
struct Instance {
    var rect: SIMD4<Float>      // x, y, width, height in points, y down
    var uv: SIMD4<Float>        // u0, v0, u1, v1 in the bound atlas
    var colorLeft: SIMD4<Float> // background gradient, left to right
    var colorRight: SIMD4<Float>
    var params: SIMD4<Float>    // rotateY angle (radians), pivot x, opacity, textured (0/1)
    var projection: SIMD4<Float> // perspective-origin x, y, perspective distance (0 = flat), unused
    var transform: SIMD4<Float>  // scale around the center, unused

    init(rect: CGRect, uv: SIMD4<Float>?, colors: (SIMD4<Float>, SIMD4<Float>)?, opacity: Float,
         angle: Float = 0, pivotX: Float = 0, perspectiveOrigin: SIMD2<Float> = .zero, perspective: Float = 0,
         scale: Float = 1) {
        self.rect = SIMD4(Float(rect.minX), Float(rect.minY), Float(rect.width), Float(rect.height))
        self.uv = uv ?? .zero
        let clear = SIMD4<Float>(repeating: 0)
        colorLeft = colors?.0 ?? clear
        colorRight = colors?.1 ?? clear
        params = SIMD4(angle, pivotX, opacity, uv == nil ? 0 : 1)
        projection = SIMD4(perspectiveOrigin.x, perspectiveOrigin.y, perspective, 0)
        transform = SIMD4(scale, 0, 0, 0)
    }
}

/// Compiled at runtime with makeLibrary(source:) to avoid SwiftPM .metal resource handling.
let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Instance {
    float4 rect;
    float4 uv;
    float4 colorLeft;
    float4 colorRight;
    float4 params;      // angle, pivotX, opacity, textured
    float4 projection;  // perspective origin xy, perspective distance
    float4 transform;   // scale
};

struct VOut {
    float4 position [[position]];
    float2 uv;
    float gradient;
    float4 colorLeft [[flat]];
    float4 colorRight [[flat]];
    float2 opacityTextured [[flat]];
};

vertex VOut tile_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                        constant Instance *instances [[buffer(0)]],
                        constant float2 &viewSize [[buffer(1)]]) {
    Instance inst = instances[iid];
    float2 corner = float2(vid & 1, vid >> 1);           // triangle strip
    float2 center = inst.rect.xy + inst.rect.zw * 0.5;
    float2 p = center + (corner - 0.5) * inst.rect.zw * inst.transform.x;   // page coords, y down

    // CSS rotateY(a) around transform-origin x = pivot:
    //   x' = cos(a) * x + sin(a) * z,  z' = -sin(a) * x + cos(a) * z   (z toward viewer, z = 0 here)
    float a = inst.params.x;
    float lx = p.x - inst.params.y;
    float x = inst.params.y + cos(a) * lx;
    float z = -sin(a) * lx;

    // CSS perspective(d) around perspective-origin: scale by d / (d - z).
    // Expressed as clip-space w so the GPU does perspective-correct UVs.
    float d = inst.projection.z;
    // Kept positive, so far-off tiles swinging toward the viewer can't pass behind the eye
    float w = d > 0 ? max((d - z) / d, 0.2) : 1.0;
    float2 po = inst.projection.xy;
    float2 proj = po + (float2(x, p.y) - po) / w;

    float2 ndc = float2(proj.x / viewSize.x * 2.0 - 1.0, 1.0 - proj.y / viewSize.y * 2.0);
    VOut out;
    out.position = float4(ndc * w, 0.0, w);
    out.uv = mix(inst.uv.xy, inst.uv.zw, corner);
    out.gradient = corner.x;
    out.colorLeft = inst.colorLeft;
    out.colorRight = inst.colorRight;
    out.opacityTextured = inst.params.zw;
    return out;
}

fragment float4 tile_fragment(VOut in [[stage_in]], texture2d<float> atlas [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 bg = mix(in.colorLeft, in.colorRight, in.gradient);   // -webkit-gradient(linear, left top, right top, ...)
    float4 text = in.opacityTextured.y > 0.5 ? atlas.sample(s, in.uv) : float4(0); // premultiplied white text
    float4 c = bg * (1.0 - text.a) + text;
    return c * in.opacityTextured.x;   // premultiplied output
}
"""

/// Something that produces the quads to draw for a frame.
@MainActor
protocol FrameSource: AnyObject {
    func frame(now: CFTimeInterval, viewSize: CGSize) -> [DrawBatch]
    /// True when there's nothing to draw. The renderer then clears once and stops presenting frames,
    /// so a transparent view over the video costs nothing.
    var isIdle: Bool { get }
    /// Points on screen per layout unit (CSS px).
    var zoom: CGFloat { get }
}

extension FrameSource {
    var isIdle: Bool { false }
    var zoom: CGFloat { Layout.zoom }
}

@MainActor
final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    weak var source: (any FrameSource)?
    /// Bound for batches without a texture (plain colored quads), so the shader always has one.
    private let placeholderTexture: MTLTexture
    /// Whether the last presented frame was empty, i.e. there's no need to draw until something shows up.
    private var presentedIdleFrame = false

    init(view: MTKView) {
        device = view.device!
        queue = device.makeCommandQueue()!
        let library = try! device.makeLibrary(source: shaderSource, options: nil)
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "tile_vertex")
        desc.fragmentFunction = library.makeFunction(name: "tile_fragment")
        desc.rasterSampleCount = view.sampleCount
        let ca = desc.colorAttachments[0]!
        ca.pixelFormat = view.colorPixelFormat
        ca.isBlendingEnabled = true
        ca.sourceRGBBlendFactor = .one
        ca.sourceAlphaBlendFactor = .one
        ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
        ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try! device.makeRenderPipelineState(descriptor: desc)
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        placeholderTexture = device.makeTexture(descriptor: texDesc)!
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let source else { return }
        let idle = source.isIdle
        if idle && presentedIdleFrame { return }
        presentedIdleFrame = idle
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        let size = Self.layoutSize(of: view.bounds.size, zoom: source.zoom)
        encode(idle ? [] : source.frame(now: CACurrentMediaTime(), viewSize: size), viewSize: size, into: enc)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    /// The view's size in layout units (CSS px), which frame sources lay out in.
    static func layoutSize(of viewSize: CGSize, zoom: CGFloat) -> CGSize {
        CGSize(width: viewSize.width / zoom, height: viewSize.height / zoom)
    }

    /// One instanced draw call per batch (each batch shares one atlas texture).
    func encode(_ batches: [DrawBatch], viewSize size: CGSize, into enc: MTLRenderCommandEncoder) {
        enc.setRenderPipelineState(pipeline)
        var viewSize = SIMD2<Float>(Float(size.width), Float(size.height))
        enc.setVertexBytes(&viewSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        for batch in batches where !batch.instances.isEmpty {
            let length = MemoryLayout<Instance>.stride * batch.instances.count
            guard let buffer = device.makeBuffer(bytes: batch.instances, length: length) else { continue }
            enc.setVertexBuffer(buffer, offset: 0, index: 0)
            enc.setFragmentTexture(batch.texture ?? placeholderTexture, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: batch.instances.count)
        }
    }
}

struct DrawBatch {
    var texture: MTLTexture?
    var instances: [Instance]
}

extension Renderer {
    /// Renders one frame offscreen (same pipeline, MSAA resolved) and writes it as a PNG.
    /// Used by the CMI_SNAPSHOT_DIR self-test, since screen capture isn't always permitted.
    func snapshot(size: CGSize, scale: CGFloat, to url: URL) {
        guard let source else { return }
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
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .multisampleResolve
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        let layoutSize = Self.layoutSize(of: size, zoom: source.zoom)
        encode(source.frame(now: CACurrentMediaTime(), viewSize: layoutSize), viewSize: layoutSize, into: enc)
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
