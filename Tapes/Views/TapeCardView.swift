import SwiftUI
import AVFoundation
import UIKit
import PhotosUI
import UniformTypeIdentifiers

enum ImportSource {
    case leftPlaceholder(index: Int)
    case rightPlaceholder(index: Int)
    case centerFAB
}


// MARK: - PHPickerResult Extension

extension Array where Element == PHPickerResult {
    func loadPickedMediaOrdered() async -> [PickedMediaItem] {
        var ordered: [PickedMediaItem?] = []
        for _ in 0..<self.count {
            ordered.append(nil)
        }
        await withTaskGroup(of: (Int, PickedMediaItem?)?.self) { group in
            for (idx, result) in self.enumerated() {
                group.addTask {
                    let p = result.itemProvider
                    // Prefer movie first
                    if p.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                        do {
                            let url = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                                p.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                                    if let error = error {
                                        continuation.resume(throwing: error)
                                    } else if let url = url {
                                        continuation.resume(returning: url)
                                    } else {
                                        continuation.resume(throwing: NSError(domain: "NoURL", code: -1))
                                    }
                                }
                            }
                            let dst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                            try? FileManager.default.removeItem(at: dst)
                            try FileManager.default.copyItem(at: url, to: dst)
                            print("✅ Loaded movie → \(dst.lastPathComponent)")
                            return (idx, .video(dst))
                        } catch {
                            print("❌ Movie load failed: \(error)")
                            return (idx, nil)
                        }
                    }
                    if p.canLoadObject(ofClass: UIImage.self) {
                        do {
                            let obj = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
                                p.loadObject(ofClass: UIImage.self) { image, error in
                                    if let error = error {
                                        continuation.resume(throwing: error)
                                    } else if let image = image as? UIImage {
                                        continuation.resume(returning: image)
                                    } else {
                                        continuation.resume(throwing: NSError(domain: "NoImage", code: -1))
                                    }
                                }
                            }
                            print("✅ Loaded image")
                            return (idx, .photo(obj))
                        } catch {
                            print("❌ Image load failed: \(error)")
                        }
                    }
                    print("⚠️ Unsupported provider at index \(idx)")
                    return (idx, nil)
                }
            }
            for await pair in group {
                guard let (idx, media) = pair else { continue }
                ordered[idx] = media
            }
        }
        return ordered.compactMap { $0 }
    }
}



struct TapeCardView: View {
    let tape: Tape
    let onSettings: () -> Void
    let onPlay: () -> Void
    let onAirPlay: () -> Void
    let onThumbnailDelete: (Clip) -> Void
    let onClipInserted: (Clip, Int) -> Void
    let onClipInsertedAtPlaceholder: (Clip, CarouselItem) -> Void
    let onMediaInserted: ([PickedMedia], InsertionStrategy) -> Void
    
    @EnvironmentObject var tapeStore: TapesStore
    @StateObject private var castManager = CastManager.shared
    @State private var insertionIndex: Int = 0
    @State private var fabMode: FABMode = .camera
    @State private var showingMediaPicker = false
    @State private var importSource: ImportSource? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title row
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                // Left group: Title (hug) + 4 + pencil
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(tape.title)
                        .font(Tokens.Typography.title)
                        .foregroundColor(Tokens.Colors.onSurface)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
                    
                    Image(systemName: "pencil")
                        .font(Tokens.Typography.title)
                        .foregroundColor(Tokens.Colors.onSurface)
                        .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                
                // 32pt minimum gap
                Spacer(minLength: 32)
                
                // Right group: gear 16 cast? 16 play
                HStack(spacing: 16) {
                    // Settings button
                    Button(action: onSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Tokens.Colors.onSurface)
                    }
                    
                    // AirPlay button (only show if available devices)
                    if castManager.hasAvailableDevices {
                        Button(action: onAirPlay) {
                            Image(systemName: "airplayvideo")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(Tokens.Colors.onSurface)
                        }
                    }
                    
                    // Play button
                    Button(action: onPlay) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Tokens.Colors.onSurface)
                    }
                }
            }
            .padding(.horizontal, Tokens.Spacing.m)
            .padding(.top, Tokens.Spacing.m)
            
            // Timeline container
            let screenW = UIScreen.main.bounds.width
            let thumbW = floor((screenW - Tokens.FAB.size) / 2.0)
            let thumbH = floor(thumbW * 9.0 / 16.0)
            
            ZStack(alignment: .center) {
                // 1) Thumbnails / scrollable carousel
                ClipCarousel(
                    tape: tape,
                    thumbSize: CGSize(width: thumbW, height: thumbH),
                    insertionIndex: $insertionIndex,
                    onPlaceholderTap: { item in
                        // Store import source and show picker
                        switch item {
                        case .startPlus:
                            importSource = .leftPlaceholder(index: 0)
                        case .endPlus:
                            importSource = .rightPlaceholder(index: tape.clips.count)
                        case .clip:
                            importSource = .centerFAB // Fallback
                        }
                        showingMediaPicker = true
                    }
                )
                .zIndex(0) // always behind the line and FAB
                
                // 2) Red center line (between clips and FAB)
                Rectangle()
                    .fill(Tokens.Colors.red.opacity(0.9))
                    .frame(width: 2, height: thumbH)
                    .allowsHitTesting(false)
                    .zIndex(1) // above thumbnails, below FAB
                
                // 3) Floating action button (camera)
                FabSwipableIcon(mode: $fabMode) {
                    // Handle FAB tap action based on mode
                    switch fabMode {
                    case .gallery:
                        importSource = .centerFAB
                        showingMediaPicker = true
                    case .camera:
                        // Handle camera action
                        break
                    case .transition:
                        // Handle transition action
                        break
                    }
                }
                .frame(width: Tokens.FAB.size, height: Tokens.FAB.size)
                .zIndex(2) // on top of everything
            }
            .frame(height: thumbH)
            .padding(.vertical, Tokens.Spacing.m)
        }
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .fill(Tokens.Colors.card)
        )
        .sheet(isPresented: $showingMediaPicker) {
            SystemMediaPicker(
                isPresented: $showingMediaPicker,
                allowImages: true,
                allowVideos: true
            ) { results in
                print("🧩 onPick called with \(results.count) result(s)")
                guard !results.isEmpty else { return }
                Task { @MainActor in
                    let picked = await results.loadPickedMediaOrdered()
                    print("📦 Converted to PickedMedia count = \(picked.count)")
                    guard !picked.isEmpty else {
                        print("⚠️ No picked media resolved; aborting insert.")
                        return
                    }

                    tapeStore.insertAtCenter(tapeID: tape.id, picked: picked)
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func processPickerResults(_ results: [PHPickerResult]) async -> [PickedMedia] {
        var pickedMedia: [PickedMedia] = []
        
        for result in results {
            do {
                // Try to load as video first
                let movie = try await withCheckedThrowingContinuation { continuation in
                    result.itemProvider.loadTransferable(type: Movie.self) { result in
                        continuation.resume(with: result)
                    }
                }
                
                let thumbnail = await generateThumbnail(from: movie.url)
                let duration = await getVideoDuration(url: movie.url)
                
                pickedMedia.append(PickedMedia(
                    type: .video,
                    localURL: movie.url,
                    thumbnail: thumbnail,
                    duration: duration
                ))
            } catch {
                // Try to load as image
                do {
                    let imageData = try await withCheckedThrowingContinuation { continuation in
                        result.itemProvider.loadTransferable(type: Data.self) { result in
                            continuation.resume(with: result)
                        }
                    }
                    
                    if let uiImage = UIImage(data: imageData) {
                        let thumbnail = uiImage
                        let duration = Tokens.Timing.photoDefaultDuration
                        
                        pickedMedia.append(PickedMedia(
                            type: .image,
                            imageData: imageData,
                            thumbnail: thumbnail,
                            duration: duration
                        ))
                    }
                } catch {
                    print("Error loading media item: \(error)")
                }
            }
        }
        
        return pickedMedia
    }
    
    private func generateThumbnail(from url: URL) async -> UIImage? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 320, height: 320)
        
        do {
            let cgImage = try await imageGenerator.image(at: .zero).image
            return UIImage(cgImage: cgImage)
        } catch {
            print("Error generating thumbnail: \(error)")
            return nil
        }
    }
    
    private func getVideoDuration(url: URL) async -> TimeInterval {
        let asset = AVAsset(url: url)
        let duration = try? await asset.load(.duration)
        return CMTimeGetSeconds(duration ?? .zero)
    }
}

#Preview("Dark Mode") {
    TapeCardView(
        tape: Tape.sampleTapes[0],
        onSettings: {},
        onPlay: {},
        onAirPlay: {},
        onThumbnailDelete: { _ in },
        onClipInserted: { _, _ in },
        onClipInsertedAtPlaceholder: { _, _ in },
        onMediaInserted: { _, _ in }
    )
    .environmentObject(TapesStore())  // lightweight preview store
    .preferredColorScheme(ColorScheme.dark)
    .padding()
    .background(Tokens.Colors.bg)
}

#Preview("Light Mode") {
    TapeCardView(
        tape: Tape.sampleTapes[0],
        onSettings: {},
        onPlay: {},
        onAirPlay: {},
        onThumbnailDelete: { _ in },
        onClipInserted: { _, _ in },
        onClipInsertedAtPlaceholder: { _, _ in },
        onMediaInserted: { _, _ in }
    )
    .environmentObject(TapesStore())  // lightweight preview store
    .preferredColorScheme(ColorScheme.light)
    .padding()
    .background(Tokens.Colors.bg)
}