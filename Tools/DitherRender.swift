import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

@main
enum DitherRender {
    static func main() throws {
        if CommandLine.arguments.dropFirst().first == "--benchmark" {
            try benchmark()
            return
        }
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "DitherRender", code: 1, userInfo: [NSLocalizedDescriptionKey: "Usage: DitherRender output.png or DitherRender --benchmark"])
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "DitherRender", code: 2, userInfo: [NSLocalizedDescriptionKey: "Metal device is unavailable"])
        }
        let width = 640
        let height = 360
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw NSError(domain: "DitherRender", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not allocate output texture"])
        }
        let renderer = try DitherMetalRenderer()
        var configuration = DitherConfiguration()
        configuration.intro = false
        let bytesPerRow = width * 4

        let baseline = try renderChecksum(renderer: renderer, texture: texture, configuration: configuration, width: width, height: height)
        guard baseline.checksum != 0, baseline.uniqueBytes > 2 else {
            throw NSError(domain: "DitherRender", code: 6, userInfo: [NSLocalizedDescriptionKey: "Rendered output is empty or uniform"])
        }

        var frequencyConfiguration = configuration
        frequencyConfiguration.waveFrequency = 7
        let frequency = try renderChecksum(renderer: renderer, texture: texture, configuration: frequencyConfiguration, width: width, height: height)
        guard baseline.checksum != frequency.checksum else {
            throw NSError(domain: "DitherRender", code: 7, userInfo: [NSLocalizedDescriptionKey: "Wave frequency did not change rendered output"])
        }

        var bayerConfiguration = configuration
        bayerConfiguration.ditherMode = 1
        let bayer = try renderChecksum(renderer: renderer, texture: texture, configuration: bayerConfiguration, width: width, height: height)
        guard baseline.checksum != bayer.checksum else {
            throw NSError(domain: "DitherRender", code: 8, userInfo: [NSLocalizedDescriptionKey: "Bayer mode did not change rendered output"])
        }

        var paletteConfiguration = configuration
        paletteConfiguration.palette = [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1)]
        let palette = try renderChecksum(renderer: renderer, texture: texture, configuration: paletteConfiguration, width: width, height: height)
        guard baseline.checksum != palette.checksum else {
            throw NSError(domain: "DitherRender", code: 9, userInfo: [NSLocalizedDescriptionKey: "Palette did not change rendered output"])
        }

        let repeatRender = try renderChecksum(renderer: renderer, texture: texture, configuration: configuration, width: width, height: height)
        let repeatRenderAgain = try renderChecksum(renderer: renderer, texture: texture, configuration: configuration, width: width, height: height)
        guard repeatRender.checksum == repeatRenderAgain.checksum else {
            throw NSError(domain: "DitherRender", code: 10, userInfo: [NSLocalizedDescriptionKey: "Static render was not deterministic"])
        }

        var gapConfiguration = configuration
        gapConfiguration.gap = 0.2
        let gap = try renderChecksum(renderer: renderer, texture: texture, configuration: gapConfiguration, width: width, height: height)
        guard gap.checksum != baseline.checksum else {
            throw NSError(domain: "DitherRender", code: 12, userInfo: [NSLocalizedDescriptionKey: "Grid gap did not change rendered output"])
        }

        var radiusConfiguration = configuration
        radiusConfiguration.cornerRadius = 0.35
        let radius = try renderChecksum(renderer: renderer, texture: texture, configuration: radiusConfiguration, width: width, height: height)
        guard radius.checksum != baseline.checksum else {
            throw NSError(domain: "DitherRender", code: 13, userInfo: [NSLocalizedDescriptionKey: "Corner radius did not change rendered output"])
        }

        var whiteBackground = configuration
        whiteBackground.backgroundColor = SIMD3<Float>(repeating: 1)
        let white = try renderChecksum(renderer: renderer, texture: texture, configuration: whiteBackground, width: width, height: height)
        guard white.checksum != baseline.checksum else {
            throw NSError(domain: "DitherRender", code: 14, userInfo: [NSLocalizedDescriptionKey: "Background color did not change rendered output"])
        }

        var boundsConfiguration = configuration
        boundsConfiguration.pixelSize = 1000
        try renderer.render(to: texture, width: width, height: height, cell: 1000, configuration: boundsConfiguration, advance: false)
        var boundsPixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        texture.getBytes(&boundsPixels, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard boundsPixels.count == height * bytesPerRow else {
            throw NSError(domain: "DitherRender", code: 11, userInfo: [NSLocalizedDescriptionKey: "Bounds render returned an invalid pixel count"])
        }

        try verifyOutputMatrix(device: device, renderer: renderer)

        try renderer.render(to: texture, width: width, height: height, cell: 4, configuration: configuration, advance: false)
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        texture.getBytes(&pixels, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let data = Data(bytes: pixels, count: pixels.count)
        guard let provider = CGDataProvider(data: data as CFData), let colorSpace = CGColorSpace(name: CGColorSpace.sRGB), let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent), let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "DitherRender", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not create PNG destination"])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "DitherRender", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not write PNG"])
        }
        print("DitherRender wrote \(CommandLine.arguments[1]) (checksum \(baseline.checksum))")
    }

    private static func benchmark() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "DitherRender", code: 2, userInfo: [NSLocalizedDescriptionKey: "Metal device is unavailable"])
        }
        let renderer = try DitherMetalRenderer()
        var configuration = DitherConfiguration()
        configuration.intro = false
        let frames = 120

        for size in [(640, 360, 2), (1920, 1080, 2), (2560, 1664, 4)] {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: size.0, height: size.1, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw NSError(domain: "DitherRender", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not allocate benchmark texture"])
            }
            try renderer.render(to: texture, width: size.0, height: size.1, cell: size.2, configuration: configuration, advance: false)
            var cpuTotal = 0.0
            var gpuSamples: [Double] = []
            for _ in 0..<frames {
                try renderer.render(to: texture, width: size.0, height: size.1, cell: size.2, configuration: configuration)
                if let metrics = renderer.lastRenderMetrics {
                    cpuTotal += metrics.cpuElapsed
                    if let gpuElapsed = metrics.gpuElapsed {
                        gpuSamples.append(gpuElapsed)
                    }
                }
            }
            let cpuMilliseconds = cpuTotal / Double(frames) * 1_000
            let cpuText = String(format: "%.3f", cpuMilliseconds)
            if gpuSamples.count == frames {
                let sorted = gpuSamples.sorted()
                let average = gpuSamples.reduce(0, +) / Double(frames) * 1_000
                let gpuText = String(format: "%.3f", average)
                let p95Text = String(format: "%.3f", sorted[Int(Double(frames - 1) * 0.95)] * 1_000)
                print("benchmark \(size.0)x\(size.1), cell \(size.2): \(frames) frames, submission \(cpuText) ms/frame, GPU mean \(gpuText) ms, p95 \(p95Text) ms")
            } else {
                print("benchmark \(size.0)x\(size.1), cell \(size.2): \(frames) frames, submission \(cpuText) ms/frame, GPU unavailable (\(gpuSamples.count)/\(frames) samples)")
            }
            configuration.pixelSize = 2
        }
    }

    private static func verifyOutputMatrix(device: MTLDevice, renderer: DitherMetalRenderer) throws {
        let width = 641
        let height = 359
        let cell = 3
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw NSError(domain: "DitherRender", code: 15, userInfo: [NSLocalizedDescriptionKey: "Could not allocate output matrix texture"])
        }
        var configurations: [(String, DitherConfiguration)] = []
        var base = DitherConfiguration()
        base.intro = false
        configurations.append(("odd-base", base))
        var gap = base
        gap.gap = 0.2
        gap.cornerRadius = 0.35
        configurations.append(("odd-gap-radius", gap))
        var transparent = gap
        transparent.transparent = true
        configurations.append(("odd-transparent", transparent))
        var palette = gap
        palette.palette = [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1)]
        configurations.append(("odd-palette", palette))
        for mode in 0...7 {
            var modeConfiguration = gap
            modeConfiguration.ditherMode = mode
            configurations.append(("odd-mode-\(mode)", modeConfiguration))
        }
        var checksums: [String: UInt64] = [:]
        for (name, configuration) in configurations {
            let result = try renderChecksum(renderer: renderer, texture: texture, configuration: configuration, width: width, height: height, cell: cell)
            checksums[name] = result.checksum
            print("verify \(name) \(width)x\(height), cell \(cell): checksum \(result.checksum)")
        }
        guard checksums["odd-base"] != checksums["odd-gap-radius"],
              checksums["odd-gap-radius"] == checksums["odd-transparent"],
              checksums["odd-gap-radius"] != checksums["odd-palette"] else {
            throw NSError(domain: "DitherRender", code: 16, userInfo: [NSLocalizedDescriptionKey: "Output matrix settings did not change rendered pixels"])
        }
        guard Set((0...7).compactMap { checksums["odd-mode-\($0)"] }).count > 5 else {
            throw NSError(domain: "DitherRender", code: 17, userInfo: [NSLocalizedDescriptionKey: "Dither mode output matrix was not varied"])
        }
    }

    private static func renderChecksum(renderer: DitherMetalRenderer, texture: MTLTexture, configuration: DitherConfiguration, width: Int, height: Int, cell: Int = 4) throws -> (checksum: UInt64, uniqueBytes: Int) {
        try renderer.render(to: texture, width: width, height: height, cell: cell, configuration: configuration, advance: false)
        var pixels = [UInt8](repeating: 0, count: height * width * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let checksum = pixels.reduce(UInt64(0)) { partial, byte in
            (partial &* 33) &+ UInt64(byte)
        }
        return (checksum, Set(pixels).count)
    }
}
