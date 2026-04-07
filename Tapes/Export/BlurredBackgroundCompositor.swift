import AVFoundation
import CoreImage

// MARK: - Custom Instruction

final class BlurredBackgroundInstruction: NSObject, AVVideoCompositionInstructionProtocol {

    struct LayerInfo {
        let trackID: CMPersistentTrackID
        let fitStartTransform: CGAffineTransform
        let fitEndTransform: CGAffineTransform
        let fillStartTransform: CGAffineTransform
        let fillEndTransform: CGAffineTransform
        let startOpacity: Float
        let endOpacity: Float
        let needsBlurBackground: Bool
    }

    let theTimeRange: CMTimeRange
    let layers: [LayerInfo]

    var timeRange: CMTimeRange { theTimeRange }
    var enablePostProcessing: Bool { true }
    var containsTweening: Bool { true }
    var requiredSourceTrackIDs: [NSValue]? {
        layers.map { NSNumber(value: $0.trackID) }
    }
    var passthroughTrackID: CMPersistentTrackID { kCMPersistentTrackID_Invalid }

    init(timeRange: CMTimeRange, layers: [LayerInfo]) {
        self.theTimeRange = timeRange
        self.layers = layers
    }
}

// MARK: - Custom Compositor

final class BlurredBackgroundCompositor: NSObject, AVVideoCompositing {

    var sourcePixelBufferAttributes: [String: Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    var requiredPixelBufferAttributesForRenderContext: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let blurSigma: Double = 100.0
    private let blurDownscale: CGFloat = 0.25

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        autoreleasepool {
            guard let instruction = request.videoCompositionInstruction as? BlurredBackgroundInstruction else {
                request.finish(with: NSError(
                    domain: "BlurCompositor", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid instruction type"]
                ))
                return
            }

            guard let outputBuffer = request.renderContext.newPixelBuffer() else {
                request.finish(with: NSError(
                    domain: "BlurCompositor", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"]
                ))
                return
            }

            let renderSize = request.renderContext.size
            let renderBounds = CGRect(origin: .zero, size: renderSize)
            let t = interpolationProgress(
                for: request.compositionTime,
                in: instruction.theTimeRange
            )

            var canvas = CIImage(color: .black).cropped(to: renderBounds)

            for layer in instruction.layers {
                guard let sourceBuffer = request.sourceFrame(byTrackID: layer.trackID) else { continue }

                let sourceImage = CIImage(cvPixelBuffer: sourceBuffer)
                let sourceHeight = CGFloat(CVPixelBufferGetHeight(sourceBuffer))
                let opacity = lerp(layer.startOpacity, layer.endOpacity, t: Float(t))

                guard opacity > 0.001 else { continue }

                let fitTransform = interpolateTransform(
                    from: layer.fitStartTransform,
                    to: layer.fitEndTransform,
                    t: t
                )
                let ciFit = avToCITransform(
                    fitTransform,
                    sourceHeight: sourceHeight,
                    renderHeight: renderSize.height
                )

                var layerImage: CIImage

                if layer.needsBlurBackground {
                    let fillTransform = interpolateTransform(
                        from: layer.fillStartTransform,
                        to: layer.fillEndTransform,
                        t: t
                    )
                    let ciFill = avToCITransform(
                        fillTransform,
                        sourceHeight: sourceHeight,
                        renderHeight: renderSize.height
                    )

                    let downTransform = ciFill.concatenating(
                        CGAffineTransform(scaleX: blurDownscale, y: blurDownscale)
                    )
                    let upscale = CGAffineTransform(
                        scaleX: 1 / blurDownscale,
                        y: 1 / blurDownscale
                    )

                    let blurred = sourceImage
                        .transformed(by: downTransform)
                        .clampedToExtent()
                        .applyingGaussianBlur(sigma: blurSigma * Double(blurDownscale))
                        .transformed(by: upscale)
                        .cropped(to: renderBounds)

                    let fit = sourceImage
                        .transformed(by: ciFit)
                        .cropped(to: renderBounds)

                    layerImage = fit.composited(over: blurred)
                } else {
                    layerImage = sourceImage
                        .transformed(by: ciFit)
                        .cropped(to: renderBounds)
                }

                if opacity < 0.999 {
                    layerImage = layerImage.applyingFilter("CIColorMatrix", parameters: [
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity))
                    ])
                }

                canvas = layerImage.composited(over: canvas)
            }

            ciContext.render(
                canvas, to: outputBuffer,
                bounds: renderBounds,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            request.finish(withComposedVideoFrame: outputBuffer)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {}

    // MARK: - Helpers

    /// Converts an AVFoundation transform (top-left origin) to CIImage space (bottom-left origin).
    private func avToCITransform(
        _ av: CGAffineTransform,
        sourceHeight: CGFloat,
        renderHeight: CGFloat
    ) -> CGAffineTransform {
        let flipSrc = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: sourceHeight)
        let flipDst = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: renderHeight)
        return flipSrc.concatenating(av).concatenating(flipDst)
    }

    private func interpolationProgress(for time: CMTime, in range: CMTimeRange) -> CGFloat {
        let elapsed = CMTimeGetSeconds(CMTimeSubtract(time, range.start))
        let total = CMTimeGetSeconds(range.duration)
        guard total > 0, elapsed.isFinite, total.isFinite else { return 0 }
        return CGFloat(max(0, min(elapsed / total, 1)))
    }

    private func interpolateTransform(
        from a: CGAffineTransform,
        to b: CGAffineTransform,
        t: CGFloat
    ) -> CGAffineTransform {
        CGAffineTransform(
            a: a.a + (b.a - a.a) * t,
            b: a.b + (b.b - a.b) * t,
            c: a.c + (b.c - a.c) * t,
            d: a.d + (b.d - a.d) * t,
            tx: a.tx + (b.tx - a.tx) * t,
            ty: a.ty + (b.ty - a.ty) * t
        )
    }

    private func lerp(_ a: Float, _ b: Float, t: Float) -> Float {
        a + (b - a) * t
    }
}
