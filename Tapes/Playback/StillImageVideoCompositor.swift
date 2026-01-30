import AVFoundation
import CoreGraphics
import UIKit

final class StillImageCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = false
    let containsTweening: Bool = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let renderSize: CGSize
    let image: CGImage
    let imageSize: CGSize
    let rotationTurns: Int
    let motionEffect: TapeCompositionBuilder.MotionEffect?
    let scaleMode: ScaleMode
    let duration: CMTime

    init(
        timeRange: CMTimeRange,
        trackID: CMPersistentTrackID,
        renderSize: CGSize,
        image: CGImage,
        imageSize: CGSize,
        rotationTurns: Int,
        motionEffect: TapeCompositionBuilder.MotionEffect?,
        scaleMode: ScaleMode
    ) {
        self.timeRange = timeRange
        self.duration = timeRange.duration
        self.requiredSourceTrackIDs = [NSNumber(value: trackID)]
        self.renderSize = renderSize
        self.image = image
        self.imageSize = imageSize
        self.rotationTurns = rotationTurns
        self.motionEffect = motionEffect
        self.scaleMode = scaleMode
        super.init()
    }
}

final class StillImageVideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let renderQueue = DispatchQueue(label: "tapes.still-image-compositor")

    var sourcePixelBufferAttributes: [String: Any]? {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async {
            guard let instruction = request.videoCompositionInstruction as? StillImageCompositionInstruction else {
                request.finish(with: NSError(domain: "StillImageVideoCompositor", code: -1))
                return
            }
            guard let buffer = request.renderContext.newPixelBuffer() else {
                request.finish(with: NSError(domain: "StillImageVideoCompositor", code: -2))
                return
            }
            self.render(
                instruction: instruction,
                into: buffer,
                time: request.compositionTime
            )
            request.finish(withComposedVideoFrame: buffer)
        }
    }

    private func render(
        instruction: StillImageCompositionInstruction,
        into pixelBuffer: CVPixelBuffer,
        time: CMTime
    ) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(instruction.renderSize.width),
            height: Int(instruction.renderSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return
        }

        context.clear(CGRect(origin: .zero, size: instruction.renderSize))
        context.interpolationQuality = .high

        let progress = normalizedProgress(time: time, duration: instruction.duration)
        let base = baseTransform(
            imageSize: instruction.imageSize,
            rotationTurns: instruction.rotationTurns,
            renderSize: instruction.renderSize,
            scaleMode: instruction.scaleMode
        )
        let transform = apply(
            effect: instruction.motionEffect,
            to: base,
            renderSize: instruction.renderSize,
            progress: progress
        )

        context.saveGState()
        context.concatenate(transform)
        context.draw(
            instruction.image,
            in: CGRect(origin: .zero, size: instruction.imageSize)
        )
        context.restoreGState()
    }

    private func normalizedProgress(time: CMTime, duration: CMTime) -> CGFloat {
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else { return 0 }
        let elapsed = CMTimeGetSeconds(time)
        guard elapsed.isFinite else { return 0 }
        let clamped = max(0, min(elapsed, durationSeconds))
        return CGFloat(clamped / durationSeconds)
    }

    private func baseTransform(
        imageSize: CGSize,
        rotationTurns: Int,
        renderSize: CGSize,
        scaleMode: ScaleMode
    ) -> CGAffineTransform {
        let baseWidth = imageSize.width
        let baseHeight = imageSize.height
        guard baseWidth > 0, baseHeight > 0 else { return .identity }

        let rotatedWidth = rotationTurns % 2 == 0 ? baseWidth : baseHeight
        let rotatedHeight = rotationTurns % 2 == 0 ? baseHeight : baseWidth

        let scaleX = renderSize.width / rotatedWidth
        let scaleY = renderSize.height / rotatedHeight
        let scale: CGFloat = scaleMode == .fill ? max(scaleX, scaleY) : min(scaleX, scaleY)

        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: renderSize.width * 0.5, y: renderSize.height * 0.5)
        transform = transform.scaledBy(x: scale, y: scale)
        if rotationTurns != 0 {
            let angle = CGFloat(rotationTurns) * (.pi / 2)
            transform = transform.rotated(by: angle)
        }
        transform = transform.translatedBy(x: -baseWidth * 0.5, y: -baseHeight * 0.5)
        return transform
    }

    private func apply(
        effect: TapeCompositionBuilder.MotionEffect?,
        to base: CGAffineTransform,
        renderSize: CGSize,
        progress: CGFloat
    ) -> CGAffineTransform {
        guard let effect else { return base }
        let scale = lerp(effect.startScale, effect.endScale, progress: progress)
        let offsetX = lerp(effect.startOffset.x, effect.endOffset.x, progress: progress) * renderSize.width
        let offsetY = lerp(effect.startOffset.y, effect.endOffset.y, progress: progress) * renderSize.height

        let renderCenter = CGPoint(x: renderSize.width * 0.5, y: renderSize.height * 0.5)
        var effectTransform = CGAffineTransform.identity
        effectTransform = effectTransform.translatedBy(x: renderCenter.x, y: renderCenter.y)
        effectTransform = effectTransform.scaledBy(x: scale, y: scale)
        effectTransform = effectTransform.translatedBy(x: -renderCenter.x, y: -renderCenter.y)
        effectTransform = effectTransform.translatedBy(x: offsetX, y: offsetY)
        return base.concatenating(effectTransform)
    }

    private func lerp(_ start: CGFloat, _ end: CGFloat, progress: CGFloat) -> CGFloat {
        start + (end - start) * max(0, min(progress, 1))
    }
}
