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
    private let renderQueue = DispatchQueue(label: "tapes.still-image-compositor", qos: .userInteractive)
    private var cachedBaseImage: CGImage?
    private var cachedBaseSize: CGSize = .zero
    private var cachedRenderSize: CGSize = .zero

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

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        cachedBaseImage = nil
    }

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

    private func preRenderedBaseImage(for instruction: StillImageCompositionInstruction, targetSize: CGSize) -> CGImage? {
        if let cached = cachedBaseImage,
           cachedBaseSize == instruction.imageSize,
           cachedRenderSize == targetSize {
            return cached
        }

        let base = baseTransform(
            imageSize: instruction.imageSize,
            rotationTurns: instruction.rotationTurns,
            renderSize: targetSize,
            scaleMode: .fill
        )
        let w = Int(ceil(targetSize.width))
        let h = Int(ceil(targetSize.height))
        guard w > 0, h > 0 else { return nil }
        guard let ctx = CGContext(
            data: nil,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.concatenate(base)
        ctx.draw(instruction.image, in: CGRect(origin: .zero, size: instruction.imageSize))

        guard let image = ctx.makeImage() else { return nil }
        cachedBaseImage = image
        cachedBaseSize = instruction.imageSize
        cachedRenderSize = targetSize
        return image
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

        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let progress = reduceMotion ? 0 : normalizedProgress(time: time, duration: instruction.duration)

        if let effect = instruction.motionEffect {
            let scale = lerp(effect.startScale, effect.endScale, progress: progress)

            if instruction.scaleMode == .fit {
                let clipRect = fittedRect(
                    imageSize: instruction.imageSize,
                    rotationTurns: instruction.rotationTurns,
                    renderSize: instruction.renderSize
                )
                guard let baseImage = preRenderedBaseImage(for: instruction, targetSize: clipRect.size) else { return }

                let offsetX = lerp(effect.startOffset.x, effect.endOffset.x, progress: progress) * clipRect.width
                let offsetY = lerp(effect.startOffset.y, effect.endOffset.y, progress: progress) * clipRect.height
                let center = CGPoint(x: clipRect.midX, y: clipRect.midY)

                context.saveGState()
                context.clip(to: clipRect)
                context.translateBy(x: center.x, y: center.y)
                context.scaleBy(x: scale, y: scale)
                context.translateBy(x: -center.x, y: -center.y)
                context.translateBy(x: offsetX, y: offsetY)
                context.interpolationQuality = .low
                context.draw(baseImage, in: clipRect)
                context.restoreGState()
            } else {
                guard let baseImage = preRenderedBaseImage(for: instruction, targetSize: instruction.renderSize) else { return }

                let offsetX = lerp(effect.startOffset.x, effect.endOffset.x, progress: progress) * instruction.renderSize.width
                let offsetY = lerp(effect.startOffset.y, effect.endOffset.y, progress: progress) * instruction.renderSize.height
                let center = CGPoint(x: instruction.renderSize.width * 0.5, y: instruction.renderSize.height * 0.5)

                context.saveGState()
                context.translateBy(x: center.x, y: center.y)
                context.scaleBy(x: scale, y: scale)
                context.translateBy(x: -center.x, y: -center.y)
                context.translateBy(x: offsetX, y: offsetY)
                context.interpolationQuality = .low
                context.draw(baseImage, in: CGRect(origin: .zero, size: instruction.renderSize))
                context.restoreGState()
            }
        } else {
            context.interpolationQuality = .high
            let base = baseTransform(
                imageSize: instruction.imageSize,
                rotationTurns: instruction.rotationTurns,
                renderSize: instruction.renderSize,
                scaleMode: instruction.scaleMode
            )
            context.saveGState()
            context.concatenate(base)
            context.draw(instruction.image, in: CGRect(origin: .zero, size: instruction.imageSize))
            context.restoreGState()
        }
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

    private func fittedRect(
        imageSize: CGSize,
        rotationTurns: Int,
        renderSize: CGSize
    ) -> CGRect {
        let rotatedWidth = rotationTurns % 2 == 0 ? imageSize.width : imageSize.height
        let rotatedHeight = rotationTurns % 2 == 0 ? imageSize.height : imageSize.width
        guard rotatedWidth > 0, rotatedHeight > 0 else {
            return CGRect(origin: .zero, size: renderSize)
        }

        let scaleX = renderSize.width / rotatedWidth
        let scaleY = renderSize.height / rotatedHeight
        let scale = min(scaleX, scaleY)

        let fittedWidth = rotatedWidth * scale
        let fittedHeight = rotatedHeight * scale
        let originX = (renderSize.width - fittedWidth) / 2
        let originY = (renderSize.height - fittedHeight) / 2

        return CGRect(x: originX, y: originY, width: fittedWidth, height: fittedHeight)
    }

    private func lerp(_ start: CGFloat, _ end: CGFloat, progress: CGFloat) -> CGFloat {
        start + (end - start) * max(0, min(progress, 1))
    }
}
