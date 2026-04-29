import SwiftUI

struct MusicWaveView: View {

    enum State: Equatable {
        case disabled
        case idle
        case playing
    }

    var state: State
    var audioLevel: CGFloat = 0

    private static let waveCount = 8

    private static let baseOpacities: [Double] = [
        0.95, 0.75, 0.85, 0.60, 0.90, 0.55, 0.70, 0.50
    ]
    private static let strokeWidths: [CGFloat] = [
        1.8, 1.2, 1.5, 0.9, 1.6, 0.8, 1.3, 0.7
    ]
    private static let frequencies: [CGFloat] = [
        0.8, 1.0, 0.65, 1.15, 0.9, 1.3, 0.75, 1.1
    ]
    private static let phases: [CGFloat] = [
        0, 0.9, 1.8, 2.7, 3.6, 4.5, 5.4, 0.5
    ]
    private static let amplitudes: [CGFloat] = [
        6.0, 7.5, 5.5, 7.0, 8.0, 5.0, 6.5, 5.8
    ]

    private static let tealColors: [Color] = [
        Color(red: 0.357, green: 0.812, blue: 0.706),
        Color(red: 0.549, green: 0.941, blue: 0.847),
        Color(red: 0.290, green: 0.722, blue: 0.631),
        Color(red: 0.690, green: 0.961, blue: 0.882),
        Color(red: 0.427, green: 0.863, blue: 0.722),
        Color(red: 0.239, green: 0.659, blue: 0.557),
        Color(red: 0.549, green: 0.941, blue: 0.847),
        Color(red: 0.357, green: 0.812, blue: 0.706)
    ]

    private static let driftSpeeds: [CGFloat] = [
        0.013, 0.019, 0.011, 0.023, 0.017, 0.029, 0.015, 0.021
    ]
    private static let driftAmplitudes: [CGFloat] = [
        0.6, 0.8, 0.5, 0.9, 0.7, 1.0, 0.55, 0.75
    ]

    // Each wave line gets 2–3 spike positions at different places
    // Stored as (position, width, strength) per wave
    private static let spikeSeeds: [[(pos: CGFloat, width: CGFloat, strength: CGFloat)]] = [
        [(0.25, 0.03, 1.0), (0.70, 0.035, 0.8)],
        [(0.40, 0.035, 0.9), (0.80, 0.03, 0.7), (0.15, 0.04, 0.6)],
        [(0.55, 0.03, 1.0), (0.20, 0.035, 0.7)],
        [(0.35, 0.04, 0.8), (0.75, 0.03, 1.0)],
        [(0.60, 0.035, 0.9), (0.30, 0.03, 0.6), (0.85, 0.04, 0.7)],
        [(0.45, 0.03, 0.8), (0.15, 0.035, 0.9)],
        [(0.70, 0.04, 1.0), (0.35, 0.03, 0.7)],
        [(0.50, 0.035, 0.9), (0.80, 0.03, 0.6), (0.20, 0.04, 0.8)]
    ]

    @SwiftUI.State private var phase: CGFloat = 0
    @SwiftUI.State private var smoothedLevel: CGFloat = 0

    private var masterOpacity: Double {
        switch state {
        case .disabled: return 0.2
        case .idle:     return 0.6
        case .playing:  return 1.0
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

                    context.opacity = opacity
                    context.stroke(
                        path,
                        with: .color(Self.tealColors[i]),
                        lineWidth: Self.strokeWidths[i]
                    )
                }
            }
            .onChange(of: timeline.date) { _, _ in
                phase += 0.05

                let target = audioLevel
                let attack: CGFloat = target > smoothedLevel ? 0.8 : 0.45
                smoothedLevel += (target - smoothedLevel) * attack
            }
        }
        .frame(height: 32)
        .drawingGroup()
    }
}
