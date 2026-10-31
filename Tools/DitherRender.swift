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

        try verifyColourEndpoints(renderer: renderer, texture: texture)
        try verifyDitherStrength(renderer: renderer, texture: texture)
        try verifyDirectionalTranslation(renderer: renderer, texture: texture)
        try verifyJoinAdjacentSquares(device: device, renderer: renderer)

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
        try verifyOptimizationParity(device: device, renderer: renderer)

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

    private static func verifyOptimizationParity(device: MTLDevice, renderer: DitherMetalRenderer) throws {
        let reference = try DitherMetalRenderer(usesFusedFieldAndCellPass: false, usesCoverageAtlas: false)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 193, height: 137, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw NSError(domain: "DitherRender", code: 40, userInfo: [NSLocalizedDescriptionKey: "Could not allocate parity target"])
        }
        var comparisons = 0
        for mode in 0..<8 {
            for shape in 0..<3 {
                for cell in [1, 2, 4, 13, 32] {
                    var configuration = DitherConfiguration()
                    configuration.intro = false
                    configuration.ditherMode = mode
                    configuration.cornerRadius = shape == 0 ? 0 : 0.35
                    configuration.gap = shape == 1 ? 0.15 : 0
                    configuration.joinAdjacentSquares = shape == 2
                    configuration.palette = cell % 2 == 0 ? [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1)] : []
                    let expected = try renderPixels(renderer: reference, texture: texture, configuration: configuration, width: texture.width, height: texture.height, cell: cell, atTime: 7.25)
                    let actual = try renderPixels(renderer: renderer, texture: texture, configuration: configuration, width: texture.width, height: texture.height, cell: cell, atTime: 7.25)
                    guard actual == expected else {
                        throw NSError(domain: "DitherRender", code: 41, userInfo: [NSLocalizedDescriptionKey: "Optimization parity failed: mode \(mode), shape \(shape), cell \(cell)"])
                    }
                    comparisons += 1
                }
            }
        }
        print("Optimization parity: \(comparisons) byte-identical comparisons passed")
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
              checksums["odd-gap-radius"] != checksums["odd-transparent"],
              checksums["odd-gap-radius"] != checksums["odd-palette"] else {
            throw NSError(domain: "DitherRender", code: 16, userInfo: [NSLocalizedDescriptionKey: "Output matrix settings did not change rendered pixels"])
        }
        guard Set((0...7).compactMap { checksums["odd-mode-\($0)"] }).count > 5 else {
            throw NSError(domain: "DitherRender", code: 17, userInfo: [NSLocalizedDescriptionKey: "Dither mode output matrix was not varied"])
        }
    }

    private static func verifyColourEndpoints(renderer: DitherMetalRenderer, texture: MTLTexture) throws {
        var configuration = DitherConfiguration()
        configuration.intro = false
        configuration.backgroundColor = SIMD3<Float>(repeating: 0.17)
        configuration.palette = [SIMD3<Float>(0.23, 0.71, 0.91), SIMD3<Float>(0.23, 0.71, 0.91)]

        configuration.brightness = -1
        for mode in 0...7 {
            configuration.ditherMode = mode
            try renderer.render(to: texture, width: texture.width, height: texture.height, cell: 4, configuration: configuration, advance: false)
            let emptyPixel = try readPixel(texture)
            try assertPixel(emptyPixel, equals: configuration.backgroundColor, named: "palette empty background mode \(mode)")
        }

        configuration.brightness = 0
        configuration.backgroundColor = .zero
        try renderer.render(to: texture, width: texture.width, height: texture.height, cell: 4, configuration: configuration, advance: false)
        var pixels = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(&pixels, bytesPerRow: texture.width * 4, from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        let backgroundPixels = stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] == 0 && pixels[$0 + 1] == 0 && pixels[$0 + 2] == 0
        }.count
        guard backgroundPixels > texture.width * texture.height / 100 else {
            throw NSError(domain: "DitherRender", code: 19, userInfo: [NSLocalizedDescriptionKey: "Multicolor must retain visible background areas in the normal field"])
        }

        configuration.brightness = 1
        configuration.ditherMode = 0
        try renderer.render(to: texture, width: texture.width, height: texture.height, cell: 4, configuration: configuration, advance: false)
        let foregroundPixel = try readPixel(texture)
        try assertPixel(foregroundPixel, equals: configuration.palette[0], named: "palette sRGB endpoint")

        configuration.palette = []
        configuration.waveColor = SIMD3<Float>(0.73, 0.15, 0.42)
        try renderer.render(to: texture, width: texture.width, height: texture.height, cell: 4, configuration: configuration, advance: false)
        try assertPixel(readPixel(texture), equals: configuration.waveColor, named: "single swatch sRGB endpoint")
        configuration.backgroundColor = SIMD3<Float>(0.61, 0.27, 0.08)
        configuration.brightness = -1
        try renderer.render(to: texture, width: texture.width, height: texture.height, cell: 4, configuration: configuration, advance: false)
        let backgroundPixel = try readPixel(texture)
        try assertPixel(backgroundPixel, equals: configuration.backgroundColor, named: "background sRGB endpoint")
    }

    private static func verifyDitherStrength(renderer: DitherMetalRenderer, texture: MTLTexture) throws {
        var configuration = DitherConfiguration()
        configuration.intro = false
        configuration.waveColor = SIMD3<Float>(0.9, 0.2, 0.1)
        configuration.backgroundColor = SIMD3<Float>(0.1, 0.1, 0.1)

        var zeroChecksums: [UInt64] = []
        for mode in 0...7 {
            configuration.ditherMode = mode
            configuration.ditherStrength = 0
            zeroChecksums.append(try renderChecksum(renderer: renderer, texture: texture, configuration: configuration, width: texture.width, height: texture.height).checksum)
        }
        guard Set(zeroChecksums).count == 1 else {
            throw NSError(domain: "DitherRender", code: 20, userInfo: [NSLocalizedDescriptionKey: "Zero dither strength did not disable every pattern"])
        }

        configuration.ditherMode = 0
        configuration.ditherStrength = 1
        let singleWave = try renderChecksum(renderer: renderer, texture: texture, configuration: configuration, width: texture.width, height: texture.height)
        configuration.ditherStrength = 0.5
        let intermediateWave = try renderChecksum(renderer: renderer, texture: texture, configuration: configuration, width: texture.width, height: texture.height)
        configuration.ditherStrength = 0
        let zeroWave = try renderChecksum(renderer: renderer, texture: texture, configuration: configuration, width: texture.width, height: texture.height)
        guard singleWave.checksum != intermediateWave.checksum,
              intermediateWave.checksum != zeroWave.checksum else {
            throw NSError(domain: "DitherRender", code: 21, userInfo: [NSLocalizedDescriptionKey: "Dither strength did not affect single-wave output"])
        }

        configuration.palette = [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1)]
        configuration.ditherStrength = 1
        let palette = try renderChecksum(renderer: renderer, texture: texture, configuration: configuration, width: texture.width, height: texture.height)
        configuration.ditherStrength = 0
        let zeroPalette = try renderChecksum(renderer: renderer, texture: texture, configuration: configuration, width: texture.width, height: texture.height)
        guard palette.checksum != zeroPalette.checksum else {
            throw NSError(domain: "DitherRender", code: 22, userInfo: [NSLocalizedDescriptionKey: "Dither strength did not affect palette output"])
        }
    }

    private static func verifyDirectionalTranslation(renderer: DitherMetalRenderer, texture: MTLTexture) throws {
        var configuration = DitherConfiguration()
        configuration.intro = false
        configuration.waveSpeed = 0.4
        configuration.ditherStrength = 0
        configuration.ditherMode = 7
        let cell = 4
        let distance = cell * 4
        let time = Float(distance) / (Float(texture.height) * configuration.waveSpeed * sqrt(2))
        let byteCount = texture.width * texture.height * 4
        for (direction, dx, dy) in [(Float(0), 0, -distance), (90, distance, 0), (180, 0, distance), (270, -distance, 0)] {
            configuration.waveDirection = direction
            try renderer.render(to: texture, width: texture.width, height: texture.height, cell: cell, configuration: configuration, advance: false, atTime: 0)
            var initial = [UInt8](repeating: 0, count: byteCount)
            texture.getBytes(&initial, bytesPerRow: texture.width * 4, from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
            try renderer.render(to: texture, width: texture.width, height: texture.height, cell: cell, configuration: configuration, advance: false, atTime: time)
            var translated = [UInt8](repeating: 0, count: byteCount)
            texture.getBytes(&translated, bytesPerRow: texture.width * 4, from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
            var matches = 0
            var compared = 0
            for y in stride(from: distance, to: texture.height - distance, by: cell) {
                for x in stride(from: distance, to: texture.width - distance, by: cell) {
                    let source = ((y - dy) * texture.width + x - dx) * 4
                    let destination = (y * texture.width + x) * 4
                    if (0..<3).allSatisfy({ abs(Int(initial[source + $0]) - Int(translated[destination + $0])) <= 1 }) {
                        matches += 1
                    }
                    compared += 1
                }
            }
            guard compared > 0, Double(matches) / Double(compared) > 0.99, initial != translated else {
                throw NSError(domain: "DitherRender", code: 23, userInfo: [NSLocalizedDescriptionKey: "Direction \(direction) did not translate the field by (\(dx), \(dy)) pixels: \(matches)/\(compared) matched"])
            }
        }
    }

    private static func verifyJoinAdjacentSquares(device: MTLDevice, renderer: DitherMetalRenderer) throws {
        let width = 96
        let height = 96
        let cell = 8
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw NSError(domain: "DitherRender", code: 24, userInfo: [NSLocalizedDescriptionKey: "Could not allocate join regression texture"])
        }

        var base = DitherConfiguration()
        base.intro = false
        base.brightness = 1
        base.cornerRadius = 0.35
        base.backgroundColor = SIMD3<Float>(repeating: 1)
        base.waveColor = .zero

        var separated = base
        separated.joinAdjacentSquares = false
        let separatedPixels = try renderPixels(renderer: renderer, texture: texture, configuration: separated, width: width, height: height, cell: cell)

        var joined = base
        joined.joinAdjacentSquares = true
        let joinedPixels = try renderPixels(renderer: renderer, texture: texture, configuration: joined, width: width, height: height, cell: cell)
        let separatedInteriorBackground = countBackgroundPixels(separatedPixels, width: width, height: height, background: base.backgroundColor, excludingBorder: true, tolerance: 64)
        let joinedInteriorBackground = countBackgroundPixels(joinedPixels, width: width, height: height, background: base.backgroundColor, excludingBorder: true, tolerance: 64)
        guard separatedInteriorBackground > 0, joinedInteriorBackground < separatedInteriorBackground else {
            throw NSError(domain: "DitherRender", code: 25, userInfo: [NSLocalizedDescriptionKey: "Joining adjacent active squares did not remove internal rounded-corner pinholes"])
        }
        guard separatedPixels != joinedPixels else {
            throw NSError(domain: "DitherRender", code: 26, userInfo: [NSLocalizedDescriptionKey: "Joining adjacent active squares did not change the fully active render"])
        }

        var gapSeparated = separated
        gapSeparated.gap = 0.2
        var gapJoined = gapSeparated
        gapJoined.joinAdjacentSquares = true
        let gapSeparatedPixels = try renderPixels(renderer: renderer, texture: texture, configuration: gapSeparated, width: width, height: height, cell: cell)
        let gapJoinedPixels = try renderPixels(renderer: renderer, texture: texture, configuration: gapJoined, width: width, height: height, cell: cell)
        guard gapSeparatedPixels == gapJoinedPixels else {
            throw NSError(domain: "DitherRender", code: 27, userInfo: [NSLocalizedDescriptionKey: "Join setting changed output when grid gap was nonzero"])
        }

        var radiusZeroSeparated = base
        radiusZeroSeparated.cornerRadius = 0
        var radiusZeroJoined = radiusZeroSeparated
        radiusZeroJoined.joinAdjacentSquares = true
        let radiusZeroSeparatedPixels = try renderPixels(renderer: renderer, texture: texture, configuration: radiusZeroSeparated, width: width, height: height, cell: cell)
        let radiusZeroJoinedPixels = try renderPixels(renderer: renderer, texture: texture, configuration: radiusZeroJoined, width: width, height: height, cell: cell)
        guard radiusZeroSeparatedPixels == radiusZeroJoinedPixels else {
            throw NSError(domain: "DitherRender", code: 28, userInfo: [NSLocalizedDescriptionKey: "Join setting changed output when corner radius was zero"])
        }

        var paletteSeparated = base
        paletteSeparated.palette = [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1)]
        paletteSeparated.joinAdjacentSquares = false
        var paletteJoined = paletteSeparated
        paletteJoined.joinAdjacentSquares = true
        let paletteSeparatedPixels = try renderPixels(renderer: renderer, texture: texture, configuration: paletteSeparated, width: width, height: height, cell: cell)
        let paletteJoinedPixels = try renderPixels(renderer: renderer, texture: texture, configuration: paletteJoined, width: width, height: height, cell: cell)
        guard paletteSeparatedPixels != paletteJoinedPixels else {
            throw NSError(domain: "DitherRender", code: 29, userInfo: [NSLocalizedDescriptionKey: "Join setting did not affect palette rendering"])
        }

        var whiteSquares = base
        whiteSquares.backgroundColor = SIMD3<Float>(repeating: 0.18)
        whiteSquares.waveColor = SIMD3<Float>(repeating: 1)
        whiteSquares.joinAdjacentSquares = false
        var joinedWhiteSquares = whiteSquares
        joinedWhiteSquares.joinAdjacentSquares = true
        let whiteSeparatedPixels = try renderPixels(renderer: renderer, texture: texture, configuration: whiteSquares, width: width, height: height, cell: cell)
        let whiteJoinedPixels = try renderPixels(renderer: renderer, texture: texture, configuration: joinedWhiteSquares, width: width, height: height, cell: cell)
        guard whiteSeparatedPixels != whiteJoinedPixels else {
            throw NSError(domain: "DitherRender", code: 30, userInfo: [NSLocalizedDescriptionKey: "Join setting did not affect white square rendering on a dark background"])
        }
    }

    private static func renderPixels(renderer: DitherMetalRenderer, texture: MTLTexture, configuration: DitherConfiguration, width: Int, height: Int, cell: Int, atTime: Float? = nil) throws -> [UInt8] {
        try renderer.render(to: texture, width: width, height: height, cell: cell, configuration: configuration, advance: false, atTime: atTime)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    private static func countBackgroundPixels(_ pixels: [UInt8], width: Int, height: Int, background: SIMD3<Float>, excludingBorder: Bool, tolerance: Int = 1) -> Int {
        let expected = SIMD3<Int>(
            Int((background.x * 255).rounded()),
            Int((background.y * 255).rounded()),
            Int((background.z * 255).rounded())
        )
        let xRange = excludingBorder ? 1..<(width - 1) : 0..<width
        let yRange = excludingBorder ? 1..<(height - 1) : 0..<height
        var count = 0
        for y in yRange {
            for x in xRange {
                let offset = (y * width + x) * 4
                let pixel = SIMD3<Int>(Int(pixels[offset + 2]), Int(pixels[offset + 1]), Int(pixels[offset]))
                if max(abs(pixel.x - expected.x), max(abs(pixel.y - expected.y), abs(pixel.z - expected.z))) <= tolerance {
                    count += 1
                }
            }
        }
        return count
    }

    private static func readPixel(_ texture: MTLTexture) throws -> SIMD3<Float> {
        var pixel = [UInt8](repeating: 0, count: 4)
        texture.getBytes(&pixel, bytesPerRow: 4, from: MTLRegionMake2D(texture.width / 2, texture.height / 2, 1, 1), mipmapLevel: 0)
        return SIMD3<Float>(Float(pixel[2]) / 255, Float(pixel[1]) / 255, Float(pixel[0]) / 255)
    }

    private static func assertPixel(_ actual: SIMD3<Float>, equals expected: SIMD3<Float>, named name: String) throws {
        let error = max(abs(actual.x - expected.x), max(abs(actual.y - expected.y), abs(actual.z - expected.z)))
        guard error <= (1.0 / 255.0 + 0.002) else {
            throw NSError(domain: "DitherRender", code: 18, userInfo: [NSLocalizedDescriptionKey: "\(name) expected \(expected), got \(actual)"])
        }
    }

    private static func renderChecksum(renderer: DitherMetalRenderer, texture: MTLTexture, configuration: DitherConfiguration, width: Int, height: Int, cell: Int = 4, atTime: Float? = nil) throws -> (checksum: UInt64, uniqueBytes: Int) {
        try renderer.render(to: texture, width: width, height: height, cell: cell, configuration: configuration, advance: false, atTime: atTime)
        var pixels = [UInt8](repeating: 0, count: height * width * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let checksum = pixels.reduce(UInt64(0)) { partial, byte in
            (partial &* 33) &+ UInt64(byte)
        }
        return (checksum, Set(pixels).count)
    }
}
