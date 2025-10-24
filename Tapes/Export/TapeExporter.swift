import Foundation
import AVFoundation
import Photos
import CoreGraphics

// MARK: - Tape Exporter

/// TapeExporter with seeded per-boundary transitions and AUDIO fades.
public enum TapeExporter {
    public static func export(tape: Tape, completion: @escaping (URL?, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let comp = AVMutableComposition()
            guard let videoTrackA = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                  let videoTrackB = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                  let audioTrackA = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
                  let audioTrackB = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                DispatchQueue.main.async { completion(nil, nil) }
                return
            }
            let renderSize: CGSize = (tape.orientation == .portrait) ? CGSize(width: 1080, height: 1920) : CGSize(width: 1920, height: 1080)
            let fps: Int32 = 30
            let frame = CMTime(value: 1, timescale: fps)

            // Simple transition - no complex picker needed
            let seq: [TransitionStyle] = Array(repeating: .crossfade, count: max(0, tape.clips.count - 1))
            let dur = tape.transitionDuration
            let overlap = CMTime(seconds: min(max(dur, 0.0), 1.0), preferredTimescale: fps*10)

            func transformFor(track: AVAssetTrack) -> CGAffineTransform {
                let srcSize = track.naturalSize.applying(track.preferredTransform)
                let absSrc = CGSize(width: abs(srcSize.width), height: abs(srcSize.height))
                let scale: CGFloat = (tape.scaleMode == .fill)
                    ? max(renderSize.width / absSrc.width, renderSize.height / absSrc.height)
                    : min(renderSize.width / absSrc.width, renderSize.height / absSrc.height)
                var t = track.preferredTransform
                t = t.concatenating(CGAffineTransform(scaleX: scale, y: scale))
                let x = (renderSize.width - absSrc.width * scale) / 2
                let y = (renderSize.height - absSrc.height * scale) / 2
                t = t.concatenating(CGAffineTransform(translationX: x, y: y))
                return t
            }

            var videoInstrs: [AVVideoCompositionInstructionProtocol] = []
            var audioParams: [AVAudioMixInputParameters] = []

            var cursor = CMTime.zero
            var useA = true
            var prevVId: CMPersistentTrackID? = nil
            var prevAId: CMPersistentTrackID? = nil
            var bIdx = 0

            for (idx, clip) in tape.clips.enumerated() {
                guard let assetLocalId = clip.assetLocalId,
                  let asset = fetchAVAsset(localId: assetLocalId),
                      let vSrc = asset.tracks(withMediaType: .video).first else { continue }
                let aSrc = asset.tracks(withMediaType: .audio).first
                let durClip = asset.duration

                let vDst = useA ? videoTrackA : videoTrackB
                let aDst = useA ? audioTrackA : audioTrackB
                useA.toggle()

                let hasOverlap = (idx > 0 && seq[min(bIdx, max(0, seq.count-1))] != .none && overlap > .zero)
                let at = hasOverlap ? cursor - overlap : cursor

                do { try vDst.insertTimeRange(CMTimeRange(start: .zero, duration: durClip), of: vSrc, at: at) } catch { continue }
                if let a = aSrc { try? aDst.insertTimeRange(CMTimeRange(start: .zero, duration: durClip), of: a, at: at) }

                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: vDst)
                let baseT = transformFor(track: vSrc)
                layer.setTransform(baseT, at: at)

                if hasOverlap, let pV = prevVId, let pA = prevAId {
                    let prevTrack = (pV == videoTrackA.trackID) ? videoTrackA : videoTrackB
                    let prevLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: prevTrack)
                    let style = seq[min(bIdx, seq.count-1)]
                    let tr = CMTimeRange(start: at, duration: overlap)

                    switch style {
                    case .crossfade:
                        prevLayer.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 0.0, timeRange: tr)
                        layer.setOpacityRamp(fromStartOpacity: 0.0, toEndOpacity: 1.0, timeRange: tr)
                    case .slideLR, .slideRL:
                        let width = renderSize.width
                        let startX: CGFloat = (style == .slideLR) ? -width : width
                        layer.setTransformRamp(fromStart: baseT.concatenating(CGAffineTransform(translationX: startX, y: 0)),
                                               toEnd: baseT, timeRange: tr)
                        prevLayer.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 0.85, timeRange: tr)
                        layer.setOpacityRamp(fromStartOpacity: 0.85, toEndOpacity: 1.0, timeRange: tr)
                    case .none, .randomise: break
                    }

                    let vTrans = AVMutableVideoCompositionInstruction()
                    vTrans.timeRange = tr
                    vTrans.layerInstructions = [layer, prevLayer]
                    videoInstrs.append(vTrans)

                    // Audio crossfade
                    let prevA = (pA == audioTrackA.trackID) ? audioTrackA : audioTrackB
                    let pParams = AVMutableAudioMixInputParameters(track: prevA)
                    pParams.setVolumeRamp(fromStartVolume: 1.0, toEndVolume: 0.0, timeRange: tr)
                    audioParams.append(pParams)

                    let cParams = AVMutableAudioMixInputParameters(track: aDst)
                    cParams.setVolumeRamp(fromStartVolume: 0.0, toEndVolume: 1.0, timeRange: tr)
                    audioParams.append(cParams)

                    bIdx += 1
                }

                let segStart = hasOverlap ? cursor : at
                let segEnd = at + durClip
                if segEnd > segStart {
                    let seg = AVMutableVideoCompositionInstruction()
                    seg.timeRange = CMTimeRange(start: segStart, end: segEnd)
                    seg.layerInstructions = [layer]
                    videoInstrs.append(seg)
                }

                prevVId = vDst.trackID
                prevAId = aDst.trackID
                cursor = segEnd
            }

            let vcomp = AVMutableVideoComposition()
            vcomp.instructions = videoInstrs
            vcomp.renderSize = renderSize
            vcomp.frameDuration = frame

            let amix = AVMutableAudioMix()
            amix.inputParameters = audioParams

            let outURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Tape_\(UUID().uuidString).mp4")
            guard let exporter = AVAssetExportSession(asset: comp, presetName: AVAssetExportPreset1920x1080) else {
                DispatchQueue.main.async { completion(nil, nil) }
                return
            }
            exporter.outputURL = outURL
            exporter.outputFileType = .mp4
            exporter.videoComposition = vcomp
            exporter.audioMix = amix
            exporter.shouldOptimizeForNetworkUse = true
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    saveToPhotos(url: outURL) { success, assetIdentifier in
                        DispatchQueue.main.async {
                            completion(success ? outURL : nil, success ? assetIdentifier : nil)
                        }
                    }
                default:
                    DispatchQueue.main.async { completion(nil, nil) }
                }
            }
        }
    }

    private static func fetchAVAsset(localId: String) -> AVAsset? {
        let res = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil)
        guard let ph = res.firstObject else { return nil }
        let opts = PHVideoRequestOptions()
        opts.version = .current; opts.deliveryMode = .automatic; opts.isNetworkAccessAllowed = true
        let sema = DispatchSemaphore(value: 0)
        var result: AVAsset?
        PHImageManager.default().requestAVAsset(forVideo: ph, options: opts) { asset, _, _ in
            result = asset; sema.signal()
        }
        _ = sema.wait(timeout: .now() + 20)
        return result
    }

    private static func saveToPhotos(url: URL, completion: @escaping (Bool, String?) -> Void) {
        var placeholderIdentifier: String?
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            placeholderIdentifier = request?.placeholderForCreatedAsset?.localIdentifier
        }) { success, error in
            if !success {
                if let error {
                    TapesLog.photos.error("Failed to save exported video: \(error.localizedDescription, privacy: .public)")
                }
                completion(false, nil)
            } else {
                completion(true, placeholderIdentifier)
            }
        }
    }
}
