import XCTest
import AVFoundation
import CoreGraphics
@testable import Tapes

final class TapeCompositionBuilderTests: XCTestCase {

    func testCrossfadeTimelineBuildsExpectedSegments() async throws {
        let duration: Double = 1.5
        let urls = try makeTestVideos(count: 2, duration: duration)
        defer { try? cleanup(urls) }

        let clips = urls.map { Clip.fromVideo(url: $0, duration: duration) }
        var tape = Tape(clips: clips)
        tape.transition = .crossfade
        tape.transitionDuration = 0.5

        let resolver: TapeCompositionBuilder.AssetResolver = { clip in
            guard let url = clip.localURL else { throw TapeCompositionBuilder.BuilderError.assetUnavailable(clipID: clip.id) }
            return AVURLAsset(url: url)
        }

        let builder = TapeCompositionBuilder(assetResolver: resolver)
        let timeline = try await builder.prepareTimeline(for: tape)

        XCTAssertEqual(timeline.segments.count, 2)
        XCTAssertEqual(timeline.transitionSequence.count, 1)
        XCTAssertEqual(timeline.transitionSequence[0]?.style, .crossfade)

        let first = timeline.segments[0]
        let second = timeline.segments[1]
        XCTAssertEqual(first.outgoingTransition?.style, .crossfade)
        XCTAssertEqual(second.incomingTransition?.style, .crossfade)
        XCTAssertEqual(first.outgoingTransition?.duration.seconds ?? 0, 0.5, accuracy: 0.05)
        XCTAssertLessThan(timeline.totalDuration.seconds, duration * 2)
    }

    func testSlideTransitionDescriptorsRespectSlideDirection() async throws {
        let duration: Double = 1.2
        let urls = try makeTestVideos(count: 2, duration: duration)
        defer { try? cleanup(urls) }

        let clips = urls.map { Clip.fromVideo(url: $0, duration: duration) }
        var tape = Tape(clips: clips)
        tape.transition = .slideLR
        tape.transitionDuration = 0.4

        let resolver: TapeCompositionBuilder.AssetResolver = { clip in
            guard let url = clip.localURL else { throw TapeCompositionBuilder.BuilderError.assetUnavailable(clipID: clip.id) }
            return AVURLAsset(url: url)
        }

        let builder = TapeCompositionBuilder(assetResolver: resolver)
        let timeline = try await builder.prepareTimeline(for: tape)

        XCTAssertEqual(timeline.transitionSequence.count, 1)
        XCTAssertEqual(timeline.transitionSequence.first??.style, .slideLR)
        let firstSegment = timeline.segments[0]
        XCTAssertEqual(firstSegment.outgoingTransition?.style, .slideLR)
        XCTAssertEqual(firstSegment.outgoingTransition?.duration.seconds ?? 0, 0.4, accuracy: 0.05)
    }

    // MARK: - Helpers

    private func makeTestVideos(count: Int, duration: Double) throws -> [URL] {
        try (0..<count).map { _ in try VideoAssetFactory.makeSolidColorVideo(duration: duration) }
    }

    private func cleanup(_ urls: [URL]) throws {
        let fileManager = FileManager.default
        for url in urls {
            try? fileManager.removeItem(at: url)
        }
    }
}

private enum VideoAssetFactory {
    static func makeSolidColorVideo(duration: Double,
                                    size: CGSize = CGSize(width: 320, height: 240),
                                    fps: Int32 = 30) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: size.width,
                kCVPixelBufferHeightKey as String: size.height
            ]
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: fps)
        let frameCount = max(1, Int(duration * Double(fps)))

        for frameIndex in 0..<frameCount {
            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }
            if let buffer = makePixelBuffer(size: size) {
                adaptor.append(buffer, withPresentationTime: presentationTime)
            }
        }

        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()
        return url
    }

    private static func makePixelBuffer(size: CGSize) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height
        ]
        CVPixelBufferCreate(kCFAllocatorDefault,
                            Int(size.width),
                            Int(size.height),
                            kCVPixelFormatType_32ARGB,
                            attrs as CFDictionary,
                            &buffer)

        guard let pixelBuffer = buffer else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                                   width: Int(size.width),
                                   height: Int(size.height),
                                   bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
            context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0))
            context.fill(CGRect(origin: .zero, size: size))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        return pixelBuffer
    }
}
