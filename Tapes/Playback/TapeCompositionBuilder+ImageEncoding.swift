import AVFoundation
import CoreGraphics
import CoreImage
import UIKit

extension TapeCompositionBuilder {

    func createVideoAsset(
        from image: UIImage,
        clip: Clip,
        duration: Double,
        motionEffect: MotionEffect? = nil,
        scaleMode: ScaleMode = .fit,
        includeBlurredBackground: Bool = false
    ) async throws -> AVAsset {
        let cgImage = try normalizedCGImage(from: image, clip: clip)
        let rotationTurns = ((clip.rotateQuarterTurns % 4) + 4) % 4
        let targetSize = normalizedVideoSize(for: cgImage, rotationTurns: rotationTurns)
        let targetWidth = Int(targetSize.width)
        let targetHeight = Int(targetSize.height)

        let blurredImage: CGImage? = includeBlurredBackground
            ? createBlurredImage(from: cgImage, radius: 24)
            : nil

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: targetWidth,
            AVVideoHeightKey: targetHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_000_000
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: targetWidth,
                kCVPixelBufferHeightKey as String: targetHeight,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: 30)
        let totalFrames = max(1, Int(duration * 30))
        guard let pixelBufferPool = adaptor.pixelBufferPool else {
            throw BuilderError.imageEncodingFailed
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let reduceMotion = await MainActor.run { UIAccessibility.isReduceMotionEnabled }

        for frameIndex in 0..<totalFrames {
            let time = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                await Task.yield()
            }

            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer)
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else { continue }

            let progress = reduceMotion ? 0 : CGFloat(frameIndex) / CGFloat(max(1, totalFrames - 1))

            renderImage(
                cgImage: cgImage,
                into: buffer,
                targetSize: targetSize,
                rotationTurns: rotationTurns,
                colorSpace: colorSpace,
                scaleMode: scaleMode,
                motionEffect: motionEffect,
                progress: progress,
                blurredImage: blurredImage
            )

            adaptor.append(buffer, withPresentationTime: time)
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        if writer.status == .failed {
            throw writer.error ?? BuilderError.imageEncodingFailed
        }
        return AVURLAsset(url: url)
    }

    func normalizedCGImage(from image: UIImage, clip: Clip) throws -> CGImage {
        if image.imageOrientation == .up, let cgImage = image.cgImage {
            return cgImage
        }

        let pixelSize = CGSize(
            width: max(image.size.width * image.scale, 1),
            height: max(image.size.height * image.scale, 1)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard

        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: pixelSize))
        }

        guard let cgImage = rendered.cgImage else {
            throw BuilderError.assetUnavailable(clipID: clip.id)
        }
        return cgImage
    }

    func normalizedVideoSize(for cgImage: CGImage, rotationTurns: Int) -> CGSize {
        let swapAxes = rotationTurns % 2 != 0
        let baseWidth = CGFloat(cgImage.width)
        let baseHeight = CGFloat(cgImage.height)

        let rotatedWidth = swapAxes ? baseHeight : baseWidth
        let rotatedHeight = swapAxes ? baseWidth : baseHeight

        let maxLongSide: CGFloat = 1920
        let maxShortSide: CGFloat = 1080
        let longSide = max(rotatedWidth, rotatedHeight)
        let shortSide = min(rotatedWidth, rotatedHeight)

        let longScale = maxLongSide / longSide
        let shortScale = maxShortSide / shortSide
        let scale = min(min(longScale, shortScale), 1.0)

        let scaledWidth = rotatedWidth * scale
        let scaledHeight = rotatedHeight * scale

        let width = makeEvenDimension(scaledWidth)
        let height = makeEvenDimension(scaledHeight)
        return CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    func makeEvenDimension(_ value: CGFloat) -> Int {
        var intValue = max(2, Int(round(value)))
        if intValue % 2 != 0 { intValue -= 1 }
        if intValue < 2 { intValue = 2 }
        return intValue
    }

    func renderImage(
        cgImage: CGImage,
        into pixelBuffer: CVPixelBuffer,
        targetSize: CGSize,
        rotationTurns: Int,
        colorSpace: CGColorSpace,
        scaleMode: ScaleMode = .fit,
        motionEffect: MotionEffect? = nil,
        progress: CGFloat = 0,
        blurredImage: CGImage? = nil
    ) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return }

        context.clear(CGRect(origin: .zero, size: targetSize))
        context.interpolationQuality = .high

        if let blurredImage {
            drawFillImage(blurredImage, in: context, targetSize: targetSize, opacity: 0.7)
        }

        let imageSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        let baseTransform = computeBaseTransform(
            imageSize: imageSize,
            rotationTurns: rotationTurns,
            renderSize: targetSize,
            scaleMode: scaleMode
        )
        let finalTransform = applyMotionEffect(
            motionEffect,
            to: baseTransform,
            renderSize: targetSize,
            progress: progress
        )

        context.saveGState()
        context.concatenate(finalTransform)
        context.draw(cgImage, in: CGRect(origin: .zero, size: imageSize))
        context.restoreGState()
    }

    private func drawFillImage(_ image: CGImage, in context: CGContext, targetSize: CGSize, opacity: CGFloat) {
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        guard imgW > 0, imgH > 0 else { return }
        let scale = max(targetSize.width / imgW, targetSize.height / imgH)
        let drawW = imgW * scale
        let drawH = imgH * scale
        let drawRect = CGRect(
            x: (targetSize.width - drawW) / 2,
            y: (targetSize.height - drawH) / 2,
            width: drawW,
            height: drawH
        )
        context.saveGState()
        context.setAlpha(opacity)
        context.draw(image, in: drawRect)
        context.restoreGState()
    }

    private func computeBaseTransform(
        imageSize: CGSize,
        rotationTurns: Int,
        renderSize: CGSize,
        scaleMode: ScaleMode
    ) -> CGAffineTransform {
        guard imageSize.width > 0, imageSize.height > 0 else { return .identity }
        let rotatedW = rotationTurns % 2 == 0 ? imageSize.width : imageSize.height
        let rotatedH = rotationTurns % 2 == 0 ? imageSize.height : imageSize.width
        let scaleX = renderSize.width / rotatedW
        let scaleY = renderSize.height / rotatedH
        let scale = scaleMode == .fill ? max(scaleX, scaleY) : min(scaleX, scaleY)

        var t = CGAffineTransform.identity
        t = t.translatedBy(x: renderSize.width * 0.5, y: renderSize.height * 0.5)
        t = t.scaledBy(x: scale, y: scale)
        if rotationTurns != 0 {
            t = t.rotated(by: CGFloat(rotationTurns) * (.pi / 2))
        }
        t = t.translatedBy(x: -imageSize.width * 0.5, y: -imageSize.height * 0.5)
        return t
    }

    private func applyMotionEffect(
        _ effect: MotionEffect?,
        to base: CGAffineTransform,
        renderSize: CGSize,
        progress: CGFloat
    ) -> CGAffineTransform {
        guard let effect else { return base }
        let p = max(0, min(progress, 1))
        let scale = effect.startScale + (effect.endScale - effect.startScale) * p
        let offsetX = (effect.startOffset.x + (effect.endOffset.x - effect.startOffset.x) * p) * renderSize.width
        let offsetY = (effect.startOffset.y + (effect.endOffset.y - effect.startOffset.y) * p) * renderSize.height

        let cx = renderSize.width * 0.5
        let cy = renderSize.height * 0.5
        var e = CGAffineTransform.identity
        e = e.translatedBy(x: cx, y: cy)
        e = e.scaledBy(x: scale, y: scale)
        e = e.translatedBy(x: -cx, y: -cy)
        e = e.translatedBy(x: offsetX, y: offsetY)
        return base.concatenating(e)
    }

    private func createBlurredImage(from cgImage: CGImage, radius: CGFloat) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter?.outputImage else { return nil }
        return sharedCIContext.createCGImage(output, from: ciImage.extent)
    }
}
