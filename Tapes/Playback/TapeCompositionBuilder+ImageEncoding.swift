import AVFoundation
import CoreGraphics
import UIKit

extension TapeCompositionBuilder {

    func createVideoAsset(from image: UIImage, clip: Clip, duration: Double) async throws -> AVAsset {
        let cgImage = try normalizedCGImage(from: image, clip: clip)
        let rotationTurns = ((clip.rotateQuarterTurns % 4) + 4) % 4
        let targetSize = normalizedVideoSize(for: cgImage, rotationTurns: rotationTurns)
        let targetWidth = Int(targetSize.width)
        let targetHeight = Int(targetSize.height)

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

        for frameIndex in 0..<totalFrames {
            let time = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                await Task.yield()
            }

            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer)
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else { continue }

            renderImage(
                cgImage: cgImage,
                into: buffer,
                targetSize: targetSize,
                rotationTurns: rotationTurns,
                colorSpace: colorSpace
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
        colorSpace: CGColorSpace
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
        context.saveGState()
        context.translateBy(x: targetSize.width / 2, y: targetSize.height / 2)
        if rotationTurns != 0 {
            let angle = CGFloat(rotationTurns) * (.pi / 2)
            context.rotate(by: angle)
        }

        let sourceWidth = CGFloat(cgImage.width)
        let sourceHeight = CGFloat(cgImage.height)
        let rotatedWidth = rotationTurns % 2 == 0 ? sourceWidth : sourceHeight
        let rotatedHeight = rotationTurns % 2 == 0 ? sourceHeight : sourceWidth
        let scale = min(targetSize.width / rotatedWidth, targetSize.height / rotatedHeight)
        context.scaleBy(x: scale, y: scale)

        let drawRect = CGRect(
            x: -sourceWidth / 2,
            y: -sourceHeight / 2,
            width: sourceWidth,
            height: sourceHeight
        )
        context.draw(cgImage, in: drawRect)
        context.restoreGState()
    }
}
