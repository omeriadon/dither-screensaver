import simd

struct DitherConfiguration {
    var waveSpeed: Float = 0.05
    var waveFrequency: Float = 3
    var waveAmplitude: Float = 0.3
    var waveColor = SIMD3<Float>(repeating: 0.5)
    var backgroundColor = SIMD3<Float>(repeating: 0)
    var colorNum: Float = 4
    var pixelSize: Float = 2
    var disableAnimation = false
    var ditherMode = 0
    var palette: [SIMD3<Float>] = []
    var scale: Float = 1
    var contrast: Float = 1
    var brightness: Float = 0
    var intro = true
    var transparent = false
    var dpr: Float = 0
    var gap: Float = 0
    var cornerRadius: Float = 0
}
