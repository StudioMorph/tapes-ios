import SwiftUI

struct MusicWaveView: View {

    enum State: Equatable {
        case disabled
        case idle
        case playing
    }

    var state: State
    var audioLevel: CGFloat = 0

    private static let waveCount = 12

    private static let baseOpacities: [Double] = [
        0.35, 0.08, 0.25, 0.14, 0.30, 0.10,
        0.20, 0.16, 0.28, 0.09, 0.22, 0.13
    ]
    private static let strokeWidths: [CGFloat] = [
        1.8, 0.6, 1.5, 0.8, 1.6, 0.7,
        1.2, 0.9, 1.4, 0.65, 1.3, 0.75
    ]
    private static let frequencies: [CGFloat] = [
        0.8, 1.1, 0.65, 1.15, 0.9, 1.25,
        0.75, 1.05, 0.7, 1.2, 0.85, 1.0
    ]
    private static let phases: [CGFloat] = [
        0, 0.7, 1.4, 2.1, 2.8, 3.5,
        4.2, 4.9, 5.6, 0.35, 1.05, 1.75
    ]
    private static let amplitudes: [CGFloat] = [
        6.0, 7.5, 5.5, 7.0, 8.0, 5.0,
        6.5, 5.8, 7.2, 6.2, 5.3, 6.8
    ]

    private static let tealColors: [Color] = [
        Color(red: 0.357, green: 0.812, blue: 0.706),
        Color(red: 0.549, green: 0.941, blue: 0.847),
        Color(red: 0.290, green: 0.722, blue: 0.631),
        Color(red: 0.690, green: 0.961, blue: 0.882),
        Color(red: 0.427, green: 0.863, blue: 0.722),
        Color(red: 0.239, green: 0.659, blue: 0.557),
        Color(red: 0.357, green: 0.812, blue: 0.706),
        Color(red: 0.549, green: 0.941, blue: 0.847),
        Color(red: 0.290, green: 0.722, blue: 0.631),
        Color(red: 0.690, green: 0.961, blue: 0.882),
        Color(red: 0.427, green: 0.863, blue: 0.722),
        Color(red: 0.239, green: 0.659, blue: 0.557)
    ]

    private static let driftSpeeds: [CGFloat] = [
        0.013, 0.019, 0.011, 0.023, 0.017, 0.029,
        0.015, 0.021, 0.014, 0.025, 0.018, 0.022
    ]
    private static let driftAmplitudes: [CGFloat] = [
        0.6, 0.8, 0.5, 0.9, 0.7, 1.0,
        0.55, 0.75, 0.65, 0.85, 0.6, 0.7
    ]

    private static let spikeSeeds: [[(pos: CGFloat, width: CGFloat, strength: CGFloat)]] = [
        [(0.25, 0.03, 1.0), (0.70, 0.035, 0.8)],
        [(0.40, 0.035, 0.9), (0.80, 0.03, 0.7), (0.15, 0.04, 0.6)],
        [(0.55, 0.03, 1.0), (0.20, 0.035, 0.7)],
        [(0.35, 0.04, 0.8), (0.75, 0.03, 1.0)],
        [(0.60, 0.035, 0.9), (0.30, 0.03, 0.6), (0.85, 0.04, 0.7)],
        [(0.45, 0.03, 0.8), (0.15, 0.035, 0.9)],
        [(0.70, 0.04, 1.0), (0.35, 0.03, 0.7)],
        [(0.50, 0.035, 0.9), (0.80, 0.03, 0.6), (0.20, 0.04, 0.8)],
        [(0.30, 0.03, 0.9), (0.65, 0.04, 0.7)],
        [(0.45, 0.035, 0.8), (0.75, 0.03, 1.0), (0.10, 0.035, 0.6)],
        [(0.55, 0.04, 0.7), (0.25, 0.03, 0.9)],
        [(0.40, 0.03, 1.0), (0.85, 0.035, 0.8)]
    ]

    @SwiftUI.State private var phase: CGFloat = 0
    @SwiftUI.State private var smoothedLevel: CGFloat = 0

    private var masterOpacity: Double {
        switch state {
        case .disabled: return 0.3
        case .idle:     return 0.6
        case .playing:  return 0.7
        }
    }

    private static func drawSpeckles(context: inout GraphicsContext, width: CGFloat, midY: CGFloat, amplitudeScale: CGFloat, phase: CGFloat, masterOpacity: Double, audioLevel: CGFloat, isPlaying: Bool, isDisabled: Bool) {
        let baseCount = 60
        let bonusCount = isPlaying ? Int(audioLevel * 40) : 0
        let speckleCount = baseCount + bonusCount

        for s in 0..<speckleCount {
            let sf = CGFloat(s)
            let seed1 = sf * 7.31 + phase * 0.08
            let seed2 = sf * 13.17 + phase * 0.05
            let seed3 = sf * 3.73 + phase * 0.12
            let driftSeed = sf * 11.03

            let baseX = fmod(abs(sin(sf * 4.19) * 137.3), 1.0)
            let drift = sin(driftSeed + phase * 0.03) * 0.04
            let normalizedX = min(1, max(0, baseX + drift))
            let x = normalizedX * width

            let waveIndex = s % waveCount
            let amp = amplitudes[waveIndex] * amplitudeScale
            let wavePhase = phase * frequencies[waveIndex] + phases[waveIndex]
            let envelope = sin(normalizedX * .pi)
            let waveY = midY + sin(normalizedX * .pi * 2 * frequencies[waveIndex] + wavePhase) * amp * envelope

            let baseScatter = sin(seed2) * 5.0
            let audioScatter = isPlaying ? sin(seed1 * 3.0) * audioLevel * 8.0 : 0
            let y = waveY + baseScatter + audioScatter

            let baseBrightness: CGFloat = isPlaying ? 0.35 + audioLevel * 0.25 : 0.3
            let particleOpacity = (sin(seed3) * 0.3 + 0.7) * baseBrightness * masterOpacity
            let particleSize: CGFloat = 1.5 + sin(seed2 * 0.7) * 1.0
            let halfSize = particleSize / 2

            context.opacity = particleOpacity
            context.fill(
                Path(ellipseIn: CGRect(x: x - halfSize, y: y - halfSize, width: particleSize, height: particleSize)),
                with: .color(isDisabled ? Color.gray : tealColors[waveIndex])
            )
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let midY = size.height / 2
                let width = size.width
                let amplitudeScale: CGFloat = 0.5

                for i in 0..<Self.waveCount {
                    let drift = sin(phase * Self.driftSpeeds[i] * 7.0 + CGFloat(i) * 2.3) * Self.driftAmplitudes[i]
                    let currentPhase = phase * Self.frequencies[i] + Self.phases[i] + drift
                    let baseAmplitude = Self.amplitudes[i] * amplitudeScale
                    let opacity = Self.baseOpacities[i] * masterOpacity

                    let spikes = Self.spikeSeeds[i]

                    var path = Path()
                    let steps = Int(width / 2)
                    for step in 0...steps {
                        let x = CGFloat(step) / CGFloat(steps) * width
                        let normalizedX = x / width
                        let envelope = sin(normalizedX * .pi)
                        let localNoise = sin(normalizedX * 13.0 + phase * 0.7 + CGFloat(i)) * 0.15

                        var spikeBoost: CGFloat = 0
                        if state == .playing && smoothedLevel > 0.02 {
                            for spike in spikes {
                                let spikePos = spike.pos + sin(phase * 0.3 + spike.pos * 5.0) * 0.05
                                let dist = abs(normalizedX - spikePos)
                                let gauss = exp(-dist * dist / (2.0 * spike.width * spike.width))
                                spikeBoost += gauss * smoothedLevel * 22.0 * spike.strength
                            }
                        }

                        let amplitude = baseAmplitude + spikeBoost
                        let y = midY + sin(normalizedX * .pi * 2 * Self.frequencies[i] + currentPhase) * amplitude * (envelope + localNoise)

                        if step == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }

                    let color = state == .disabled ? Color.gray : Self.tealColors[i]
                    context.opacity = opacity
                    context.stroke(
                        path,
                        with: .color(color),
                        lineWidth: Self.strokeWidths[i]
                    )
                }

                Self.drawSpeckles(context: &context, width: width, midY: midY, amplitudeScale: amplitudeScale, phase: phase, masterOpacity: masterOpacity, audioLevel: smoothedLevel, isPlaying: state == .playing, isDisabled: state == .disabled)
            }
            .onChange(of: timeline.date) { _, _ in
                phase += 0.05

                let target = audioLevel
                let attack: CGFloat = target > smoothedLevel ? 0.8 : 0.45
                smoothedLevel += (target - smoothedLevel) * attack
            }
        }
        .frame(height: 60)
        .drawingGroup()
        .fixedSize(horizontal: false, vertical: true)
        .frame(height: 32)
    }
}
