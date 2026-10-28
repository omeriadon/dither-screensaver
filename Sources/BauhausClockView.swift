import AppKit
import Foundation
import Metal
import QuartzCore
import ScreenSaver
import simd

private struct FieldUniforms {
    var resolution: SIMD2<Float>
    var cell: Float
    var time: Float
    var waveSpeed: Float
    var waveFrequency: Float
    var waveAmplitude: Float
    var scale: Float
    var contrast: Float
    var brightness: Float
    var intro: Float
    var reach: Float
}

private struct DitherUniforms {
    var fieldSize: SIMD2<Int32>
    var cellDevice: Float
    var mode: Int32
    var colorNum: Float
    var wave: SIMD3<Float>
    var background: SIMD3<Float>
    var paletteCount: Int32
    var transparent: Float
    var gap: Float
    var cornerRadius: Float
    var viewportSize: SIMD2<Int32>
}

final class DitherMetalRenderer {
    struct RenderMetrics {
        let cpuElapsed: TimeInterval
        let gpuElapsed: TimeInterval?
    }

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let fieldPipeline: MTLRenderPipelineState
    private let cellPipeline: MTLRenderPipelineState
    private let ditherPipeline: MTLRenderPipelineState
    private var fieldTexture: MTLTexture?
    private var cellTexture: MTLTexture?
    private var fieldSize = MTLSize(width: 1, height: 1, depth: 1)
    private var time: Float = 0
    private var reveal: Float = 0
    private var clock = DitherAnimationClock()
    private var paletteBuffer: MTLBuffer
    private var lastPalette: [SIMD3<Float>] = []
    private(set) var lastRenderMetrics: RenderMetrics?

    init() throws {
        guard MemoryLayout<FieldUniforms>.stride == 48,
              MemoryLayout<DitherUniforms>.stride == 96 else {
            throw NSError(domain: "DitherMetal", code: 12, userInfo: [NSLocalizedDescriptionKey: "Swift and Metal uniform layouts do not match"])
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "DitherMetal", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal device is unavailable"])
        }
        guard let queue = device.makeCommandQueue() else {
            throw NSError(domain: "DitherMetal", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create Metal command queue"])
        }
        self.device = device
        self.queue = queue
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            throw NSError(domain: "DitherMetal", code: 3, userInfo: [NSLocalizedDescriptionKey: "Dither shader compilation failed: \(error)"])
        }
        guard let vertex = library.makeFunction(name: "ditherVertex"),
              let field = library.makeFunction(name: "ditherField"),
              let cell = library.makeFunction(name: "ditherCell"),
              let dither = library.makeFunction(name: "ditherUpscale") else {
            throw NSError(domain: "DitherMetal", code: 4, userInfo: [NSLocalizedDescriptionKey: "Dither shader functions are missing"])
        }
        let fieldDescriptor = MTLRenderPipelineDescriptor()
        fieldDescriptor.vertexFunction = vertex
        fieldDescriptor.fragmentFunction = field
        fieldDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        let cellDescriptor = MTLRenderPipelineDescriptor()
        cellDescriptor.vertexFunction = vertex
        cellDescriptor.fragmentFunction = cell
        cellDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
        let ditherDescriptor = MTLRenderPipelineDescriptor()
        ditherDescriptor.vertexFunction = vertex
        ditherDescriptor.fragmentFunction = dither
        ditherDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        do {
            fieldPipeline = try device.makeRenderPipelineState(descriptor: fieldDescriptor)
            cellPipeline = try device.makeRenderPipelineState(descriptor: cellDescriptor)
            ditherPipeline = try device.makeRenderPipelineState(descriptor: ditherDescriptor)
        } catch {
            throw NSError(domain: "DitherMetal", code: 5, userInfo: [NSLocalizedDescriptionKey: "Dither pipeline creation failed: \(error)"])
        }
        guard let paletteBuffer = device.makeBuffer(length: 8 * MemoryLayout<SIMD3<Float>>.stride, options: .storageModeShared) else {
            throw NSError(domain: "DitherMetal", code: 11, userInfo: [NSLocalizedDescriptionKey: "Could not allocate palette buffer"])
        }
        self.paletteBuffer = paletteBuffer
    }

    func render(to drawable: CAMetalDrawable, size: CGSize, configuration: DitherConfiguration, advance: Bool) throws {
        let drawableWidth = drawable.texture.width
        let drawableHeight = drawable.texture.height
        let ratio = Float(drawableWidth) / max(Float(size.width), 1)
        let cell = max(1, Int(configuration.pixelSize * ratio))
        try render(to: drawable.texture, width: drawableWidth, height: drawableHeight, cell: cell, configuration: configuration, advance: advance, drawable: drawable, waitUntilCompleted: false)
    }

    func render(to target: MTLTexture, width: Int, height: Int, cell: Int, configuration: DitherConfiguration, advance: Bool = true) throws {
        try render(to: target, width: width, height: height, cell: cell, configuration: configuration, advance: advance, drawable: nil, waitUntilCompleted: true)
    }

    func resetClock() {
        clock.reset()
    }

    private func render(to target: MTLTexture, width: Int, height: Int, cell: Int, configuration: DitherConfiguration, advance: Bool, drawable: CAMetalDrawable?, waitUntilCompleted: Bool) throws {
        let cpuStart = CACurrentMediaTime()
        let delta = Float(clock.advance(now: cpuStart, isAdvancing: advance))
        if advance && !configuration.disableAnimation {
            time += delta
        }
        if configuration.intro {
            reveal = min(1, reveal + delta / 1.8)
        } else {
            reveal = 1
        }
        let cell = max(1, min(cell, width, height))
        let columns = max(1, width / cell)
        let rows = max(1, height / cell)
        if fieldTexture == nil || fieldSize.width != columns || fieldSize.height != rows {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: columns, height: rows, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            fieldTexture = device.makeTexture(descriptor: descriptor)
            let cellDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: columns, height: rows, mipmapped: false)
            cellDescriptor.usage = [.renderTarget, .shaderRead]
            cellTexture = device.makeTexture(descriptor: cellDescriptor)
            fieldSize = MTLSize(width: columns, height: rows, depth: 1)
        }
        guard let fieldTexture, let cellTexture else {
            throw NSError(domain: "DitherMetal", code: 6, userInfo: [NSLocalizedDescriptionKey: "Could not allocate field texture"])
        }
        var field = FieldUniforms(resolution: SIMD2<Float>(Float(columns * cell), Float(rows * cell)), cell: Float(cell), time: time, waveSpeed: configuration.waveSpeed, waveFrequency: configuration.waveFrequency, waveAmplitude: configuration.waveAmplitude, scale: max(0.05, configuration.scale), contrast: configuration.contrast, brightness: configuration.brightness, intro: reveal, reach: 1.5)
        var dither = DitherUniforms(fieldSize: SIMD2<Int32>(Int32(columns), Int32(rows)), cellDevice: Float(cell), mode: Int32(configuration.ditherMode), colorNum: max(2, configuration.colorNum), wave: configuration.waveColor, background: configuration.backgroundColor, paletteCount: Int32(min(8, configuration.palette.count)), transparent: configuration.transparent ? 1 : 0, gap: min(0.45, max(0, configuration.gap)), cornerRadius: min(0.5, max(0, configuration.cornerRadius)), viewportSize: SIMD2<Int32>(Int32(width), Int32(height)))
        if configuration.palette != lastPalette {
            var paletteData = [SIMD3<Float>](repeating: SIMD3<Float>(), count: 8)
            for (index, color) in configuration.palette.prefix(8).enumerated() {
                paletteData[index] = color
            }
            guard let replacement = paletteData.withUnsafeBytes({ bytes in
                guard let baseAddress = bytes.baseAddress else {
                    return nil as MTLBuffer?
                }
                return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: .storageModeShared)
            }) else {
                throw NSError(domain: "DitherMetal", code: 11, userInfo: [NSLocalizedDescriptionKey: "Could not allocate palette buffer"])
            }
            paletteBuffer = replacement
            lastPalette = configuration.palette
        }
        guard let commandBuffer = queue.makeCommandBuffer() else {
            throw NSError(domain: "DitherMetal", code: 7, userInfo: [NSLocalizedDescriptionKey: "Could not create Metal command buffer"])
        }
        let fieldPass = MTLRenderPassDescriptor()
        fieldPass.colorAttachments[0].texture = fieldTexture
        fieldPass.colorAttachments[0].loadAction = .dontCare
        fieldPass.colorAttachments[0].storeAction = .store
        guard let fieldEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: fieldPass) else {
            throw NSError(domain: "DitherMetal", code: 8, userInfo: [NSLocalizedDescriptionKey: "Could not create field encoder"])
        }
        fieldEncoder.setRenderPipelineState(fieldPipeline)
        fieldEncoder.setFragmentBytes(&field, length: MemoryLayout<FieldUniforms>.stride, index: 0)
        fieldEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        fieldEncoder.endEncoding()
        let cellPass = MTLRenderPassDescriptor()
        cellPass.colorAttachments[0].texture = cellTexture
        cellPass.colorAttachments[0].loadAction = .dontCare
        cellPass.colorAttachments[0].storeAction = .store
        guard let cellEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: cellPass) else {
            throw NSError(domain: "DitherMetal", code: 8, userInfo: [NSLocalizedDescriptionKey: "Could not create cell encoder"])
        }
        cellEncoder.setRenderPipelineState(cellPipeline)
        cellEncoder.setFragmentTexture(fieldTexture, index: 0)
        cellEncoder.setFragmentBytes(&dither, length: MemoryLayout<DitherUniforms>.stride, index: 0)
        cellEncoder.setFragmentBuffer(paletteBuffer, offset: 0, index: 1)
        cellEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        cellEncoder.endEncoding()
        let finalPass = MTLRenderPassDescriptor()
        finalPass.colorAttachments[0].texture = target
        finalPass.colorAttachments[0].loadAction = .clear
        finalPass.colorAttachments[0].storeAction = .store
        finalPass.colorAttachments[0].clearColor = MTLClearColor(red: Double(configuration.backgroundColor.x), green: Double(configuration.backgroundColor.y), blue: Double(configuration.backgroundColor.z), alpha: 1)
        guard let finalEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: finalPass) else {
            throw NSError(domain: "DitherMetal", code: 9, userInfo: [NSLocalizedDescriptionKey: "Could not create composite encoder"])
        }
        finalEncoder.setRenderPipelineState(ditherPipeline)
        finalEncoder.setFragmentTexture(cellTexture, index: 0)
        finalEncoder.setFragmentBytes(&dither, length: MemoryLayout<DitherUniforms>.stride, index: 0)
        finalEncoder.setFragmentBuffer(paletteBuffer, offset: 0, index: 1)
        finalEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        finalEncoder.endEncoding()
        if let drawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
        let submissionElapsed = CACurrentMediaTime() - cpuStart
        if waitUntilCompleted {
            commandBuffer.waitUntilCompleted()
            if let error = commandBuffer.error {
                throw error
            }
            let gpuElapsed = commandBuffer.gpuStartTime > 0 && commandBuffer.gpuEndTime > commandBuffer.gpuStartTime
                ? commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
                : nil
            lastRenderMetrics = RenderMetrics(cpuElapsed: submissionElapsed, gpuElapsed: gpuElapsed)
        }
    }

    private static let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct FieldUniforms {
    float2 resolution;
    float cell;
    float time;
    float waveSpeed;
    float waveFrequency;
    float waveAmplitude;
    float scale;
    float contrast;
    float brightness;
    float intro;
    float reach;
};

struct DitherUniforms {
    int2 fieldSize;
    float cellDevice;
    int mode;
    float colorNum;
    float3 wave;
    float3 background;
    int paletteCount;
    float transparent;
    float gap;
    float cornerRadius;
    int2 viewportSize;
};

struct Raster {
    float4 position [[position]];
};

vertex Raster ditherVertex(uint id [[vertex_id]]) {
    const float2 positions[3] = {
        float2(-1.0, -1.0),
        float2(3.0, -1.0),
        float2(-1.0, 3.0)
    };
    Raster result;
    result.position = float4(positions[id], 0.0, 1.0);
    return result;
}

float4 mod289(float4 value) {
    return value - floor(value * (1.0 / 289.0)) * 289.0;
}

float4 permute(float4 value) {
    return mod289(((value * 34.0) + 1.0) * value);
}

float4 taylorInvSqrt(float4 value) {
    return 1.79284291400159 - 0.85373472095314 * value;
}

float2 fade(float2 value) {
    return value * value * value * (value * (value * 6.0 - 15.0) + 10.0);
}

float cnoise(float2 point) {
    float4 integerPart = floor(point.xyxy) + float4(0.0, 0.0, 1.0, 1.0);
    float4 fractionalPart = fract(point.xyxy) - float4(0.0, 0.0, 1.0, 1.0);
    integerPart = mod289(integerPart);
    float4 ix = integerPart.xzxz;
    float4 iy = integerPart.yyww;
    float4 fx = fractionalPart.xzxz;
    float4 fy = fractionalPart.yyww;
    float4 index = permute(permute(ix) + iy);
    float4 gx = fract(index * (1.0 / 41.0)) * 2.0 - 1.0;
    float4 gy = abs(gx) - 0.5;
    float4 tx = floor(gx + 0.5);
    gx -= tx;
    float2 g00 = float2(gx.x, gy.x);
    float2 g10 = float2(gx.y, gy.y);
    float2 g01 = float2(gx.z, gy.z);
    float2 g11 = float2(gx.w, gy.w);
    float4 normalizer = taylorInvSqrt(float4(dot(g00, g00), dot(g01, g01), dot(g10, g10), dot(g11, g11)));
    g00 *= normalizer.x;
    g01 *= normalizer.y;
    g10 *= normalizer.z;
    g11 *= normalizer.w;
    float n00 = dot(g00, float2(fx.x, fy.x));
    float n10 = dot(g10, float2(fx.y, fy.y));
    float n01 = dot(g01, float2(fx.z, fy.z));
    float n11 = dot(g11, float2(fx.w, fy.w));
    float2 fadeXY = fade(fractionalPart.xy);
    float2 nx = mix(float2(n00, n01), float2(n10, n11), fadeXY.x);
    return 2.3 * mix(nx.x, nx.y, fadeXY.y);
}

float fbm(float2 point, constant FieldUniforms &uniforms) {
    float value = 0.0;
    float amplitude = 1.0;
    for (int index = 0; index < 4; index++) {
        value += amplitude * abs(cnoise(point));
        point *= uniforms.waveFrequency;
        amplitude *= uniforms.waveAmplitude;
    }
    return value;
}

float pattern(float2 point, constant FieldUniforms &uniforms) {
    float2 shifted = point - uniforms.time * uniforms.waveSpeed;
    return fbm(point + fbm(shifted, uniforms), uniforms);
}

fragment float4 ditherField(
    Raster input [[stage_in]],
    constant FieldUniforms &uniforms [[buffer(0)]]) {
    float2 corner = (input.position.xy - 0.5) * uniforms.cell;
    float2 uv = corner / uniforms.resolution - 0.5;
    uv.x *= uniforms.resolution.x / uniforms.resolution.y;
    float2 warp = float2(0.0);
    float value = pattern((uv + warp) / max(uniforms.scale, 0.05), uniforms);
    value = (value - 0.5) * uniforms.contrast + 0.5 + uniforms.brightness;
    float show = clamp((uniforms.intro * uniforms.reach - length(uv)) / 0.45, 0.0, 1.0);
    float displayed = clamp(value, 0.0, 1.0) * show * show * (3.0 - 2.0 * show);
    return float4(floor(displayed * 255.0) / 255.0, fract(displayed * 255.0), 0.0, 1.0);
}

constant float bayer8[64] = {
    0.0 / 64.0, 48.0 / 64.0, 12.0 / 64.0, 60.0 / 64.0, 3.0 / 64.0, 51.0 / 64.0, 15.0 / 64.0, 63.0 / 64.0,
    32.0 / 64.0, 16.0 / 64.0, 44.0 / 64.0, 28.0 / 64.0, 35.0 / 64.0, 19.0 / 64.0, 47.0 / 64.0, 31.0 / 64.0,
    8.0 / 64.0, 56.0 / 64.0, 4.0 / 64.0, 52.0 / 64.0, 11.0 / 64.0, 59.0 / 64.0, 7.0 / 64.0, 55.0 / 64.0,
    40.0 / 64.0, 24.0 / 64.0, 36.0 / 64.0, 20.0 / 64.0, 43.0 / 64.0, 27.0 / 64.0, 39.0 / 64.0, 23.0 / 64.0,
    2.0 / 64.0, 50.0 / 64.0, 14.0 / 64.0, 62.0 / 64.0, 1.0 / 64.0, 49.0 / 64.0, 13.0 / 64.0, 61.0 / 64.0,
    34.0 / 64.0, 18.0 / 64.0, 46.0 / 64.0, 30.0 / 64.0, 33.0 / 64.0, 17.0 / 64.0, 45.0 / 64.0, 29.0 / 64.0,
    10.0 / 64.0, 58.0 / 64.0, 6.0 / 64.0, 54.0 / 64.0, 9.0 / 64.0, 57.0 / 64.0, 5.0 / 64.0, 53.0 / 64.0,
    42.0 / 64.0, 26.0 / 64.0, 38.0 / 64.0, 22.0 / 64.0, 41.0 / 64.0, 25.0 / 64.0, 37.0 / 64.0, 21.0 / 64.0
};

constant float bayer4[16] = {
    0.0 / 16.0, 8.0 / 16.0, 2.0 / 16.0, 10.0 / 16.0,
    12.0 / 16.0, 4.0 / 16.0, 14.0 / 16.0, 6.0 / 16.0,
    3.0 / 16.0, 11.0 / 16.0, 1.0 / 16.0, 9.0 / 16.0,
    15.0 / 16.0, 7.0 / 16.0, 13.0 / 16.0, 5.0 / 16.0
};

constant float bayer2[4] = { 0.0 / 4.0, 2.0 / 4.0, 3.0 / 4.0, 1.0 / 4.0 };

float threshold(float2 cell, int mode) {
    if (mode == 1) {
        int2 coordinate = int2(fmod(cell, 4.0));
        return bayer4[coordinate.y * 4 + coordinate.x];
    }
    if (mode == 2) {
        int2 coordinate = int2(fmod(cell, 2.0));
        return bayer2[coordinate.y * 2 + coordinate.x];
    }
    if (mode == 3) {
        float2 rotated = float2(cell.x + cell.y, cell.x - cell.y) * 0.70710678 / 4.0;
        return clamp(length(fract(rotated) - 0.5) * 1.41421356, 0.0, 0.999);
    }
    if (mode == 4) {
        return abs(fract(cell.y / 4.0) - 0.5) * 2.0 * 0.999;
    }
    if (mode == 5) {
        float first = abs(fract((cell.x + cell.y) / 6.0) - 0.5) * 2.0;
        float second = abs(fract((cell.x - cell.y) / 6.0) - 0.5) * 2.0;
        return min(first, second) * 0.999;
    }
    if (mode == 6) {
        return fract(52.9829189 * fract(dot(cell, float2(0.06711056, 0.00583715))));
    }
    if (mode == 7) {
        return 0.25;
    }
    int2 coordinate = int2(fmod(cell, 8.0));
    return bayer8[coordinate.y * 8 + coordinate.x];
}

float3 toSrgb(float3 color) {
    color = clamp(color, 0.0, 1.0);
    return mix(color * 12.92, 1.055 * pow(color, float3(1.0 / 2.4)) - 0.055, step(0.0031308, color));
}

fragment float4 ditherCell(
    Raster input [[stage_in]],
    texture2d<float, access::read> field [[texture(0)]],
    constant DitherUniforms &uniforms [[buffer(0)]],
    constant float3 *palette [[buffer(1)]]) {
    uint2 cellPixel = uint2(input.position.xy);
    float2 cell = float2(cellPixel);
    int2 maximum = uniforms.fieldSize - 1;
    int2 coordinate = clamp(int2(cell), int2(0), maximum);
    float4 sampleValue = field.read(uint2(coordinate));
    float value = sampleValue.r + sampleValue.g / 255.0;
    float thresholdValue = threshold(cell, uniforms.mode) - 0.25;
    if (uniforms.paletteCount > 1) {
        float count = float(uniforms.paletteCount);
        float paletteValue = value + thresholdValue / (count - 1.0);
        paletteValue = clamp(paletteValue - mix(0.2, 0.0, smoothstep(0.45, 0.8, paletteValue)), 0.0, 1.0);
        int index = int(floor(paletteValue * (count - 1.0) + 0.5));
        return float4(toSrgb(palette[index]), 1.0);
    }
    float levels = max(uniforms.colorNum, 1.01) - 1.0;
    float opacityValue = value + thresholdValue / levels;
    opacityValue = clamp(opacityValue - mix(0.2, 0.0, smoothstep(0.45, 0.8, opacityValue)), 0.0, 1.0);
    float alpha = floor(opacityValue * levels + 0.5) / levels;
    if (uniforms.transparent > 0.5) {
        return float4(toSrgb(uniforms.wave) * alpha, alpha);
    }
    return float4(mix(toSrgb(uniforms.background), toSrgb(uniforms.wave), alpha), 1.0);
}

fragment float4 ditherUpscale(
    Raster input [[stage_in]],
    texture2d<float, access::read> cellColors [[texture(0)]],
    constant DitherUniforms &uniforms [[buffer(0)]]) {
    int2 outputPixel = int2(input.position.xy);
    int cellSize = int(uniforms.cellDevice);
    int2 gridSize = uniforms.fieldSize * cellSize;
    int2 padding = (uniforms.viewportSize - gridSize) / 2;
    int2 gridPixel = outputPixel - padding;
    if (any(gridPixel < 0) || any(gridPixel >= gridSize)) {
        if (uniforms.transparent > 0.5 && uniforms.paletteCount <= 1) {
            return float4(0.0);
        }
        return float4(toSrgb(uniforms.background), 1.0);
    }
    uint2 pixel = uint2(gridPixel);
    float2 cell = floor(float2(pixel) / uniforms.cellDevice);
    int2 maximum = uniforms.fieldSize - 1;
    int2 coordinate = clamp(int2(cell), int2(0), maximum);
    float4 cellColor = cellColors.read(uint2(coordinate));
    float3 backgroundColor = toSrgb(uniforms.background);
    float shape = 1.0;
    if (uniforms.gap > 0.0 || uniforms.cornerRadius > 0.0) {
        float2 local = fmod(float2(pixel) + 0.5, uniforms.cellDevice);
        float2 size = float2(uniforms.cellDevice);
        float2 inset = min(uniforms.gap * size, size * 0.49);
        float2 point = local - size * 0.5;
        float2 halfSize = max(size * 0.5 - inset, float2(0.5));
        float radius = min(uniforms.cornerRadius * size.x, min(halfSize.x, halfSize.y));
        float2 distanceToCorner = abs(point) - (halfSize - radius);
        float distance = length(max(distanceToCorner, float2(0.0))) + min(max(distanceToCorner.x, distanceToCorner.y), 0.0) - radius;
        shape = 1.0 - smoothstep(-0.75, 0.75, distance);
    }
    if (uniforms.transparent > 0.5 && uniforms.paletteCount <= 1) {
        return float4(cellColor.rgb * shape, cellColor.a * shape);
    }
    return float4(mix(backgroundColor, cellColor.rgb, shape), 1.0);
}
"""
}

@objc(BauhausClockView)
public final class BauhausClockView: ScreenSaverView {
    private var renderer: DitherMetalRenderer?
    private var configuration = DitherConfiguration()
#if GEOMETRY_CLOCK_APPEX
    private let settings = GeometryClockSettings.shared
#endif

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        let metalLayer = CAMetalLayer()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        layer = metalLayer
        animationTimeInterval = 1.0 / 30.0
        do {
            renderer = try DitherMetalRenderer()
            metalLayer.device = renderer?.device
        } catch {
            NSLog("GeometryClock: Metal renderer unavailable: %@", String(describing: error))
            metalLayer.backgroundColor = NSColor.black.cgColor
        }
#if GEOMETRY_CLOCK_APPEX
        configuration = settings.configuration
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: GeometryClockSettings.didChangeNotification,
            object: nil
        )
#endif
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        renderer?.resetClock()
        guard window != nil else {
            return
        }
        renderFrame()
    }

    public override func startAnimation() {
        renderer?.resetClock()
        super.startAnimation()
    }

    public override func stopAnimation() {
        super.stopAnimation()
        renderer?.resetClock()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        renderFrame()
    }

    public override func animateOneFrame() {
        guard window != nil else {
            return
        }
        renderFrame()
    }

    @objc private func settingsDidChange() {
#if GEOMETRY_CLOCK_APPEX
        settings.reload()
        configuration = settings.configuration
#endif
        renderFrame()
    }

    private func currentConfiguration() -> DitherConfiguration {
#if GEOMETRY_CLOCK_APPEX
        return configuration
#else
        return configuration
#endif
    }

    private func renderFrame() {
        guard window != nil, let metalLayer = layer as? CAMetalLayer,
              bounds.width > 0, bounds.height > 0 else {
            return
        }
        let configuration = currentConfiguration()
        let ratio = configuration.dpr > 0 ? CGFloat(configuration.dpr) : min(window?.backingScaleFactor ?? 1, 2)
        metalLayer.drawableSize = CGSize(width: bounds.width * ratio, height: bounds.height * ratio)
        guard let drawable = metalLayer.nextDrawable() else {
            return
        }
        do {
            guard let renderer else {
                return
            }
            try renderer.render(to: drawable, size: bounds.size, configuration: configuration, advance: true)
        } catch {
            NSLog("GeometryClock: frame render failed: %@", String(describing: error))
            metalLayer.backgroundColor = NSColor.black.cgColor
        }
    }
}
