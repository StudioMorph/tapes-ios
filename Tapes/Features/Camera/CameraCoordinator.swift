import SwiftUI
import UIKit
import AVFoundation
import Photos

class CameraCoordinator: NSObject, ObservableObject {
    @Published var isPresented = false
    @Published var capturedMedia: [PickedMedia] = []

    private var completion: (([PickedMedia]) -> Void)?

    func presentCamera(completion: @escaping ([PickedMedia]) -> Void) {
        self.completion = completion
        self.capturedMedia = []

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.isPresented = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.isPresented = true
                    }
                }
            }
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func handleCapturedMedia(_ media: [PickedMedia]) {
        self.capturedMedia = media

        saveMediaToPhotosLibrary(media) { [weak self] savedMedia in
            DispatchQueue.main.async {
                self?.completion?(savedMedia)
                self?.isPresented = false
            }
        }
    }

    func handleMultiCapture(_ media: [PickedMedia]) {
        guard !media.isEmpty else {
            isPresented = false
            return
        }

        saveMediaToPhotosLibrary(media) { [weak self] savedMedia in
            DispatchQueue.main.async {
                self?.completion?(savedMedia)
                self?.isPresented = false
            }
        }
    }

    // MARK: - Photos Save

    private func saveMediaToPhotosLibrary(_ media: [PickedMedia], completion: @escaping ([PickedMedia]) -> Void) {
        guard !media.isEmpty else {
            completion([])
            return
        }

        let status = PHPhotoLibrary.authorizationStatus()

        switch status {
        case .authorized, .limited:
            performSave(media: media, completion: completion)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { newStatus in
                if newStatus == .authorized || newStatus == .limited {
                    self.performSave(media: media, completion: completion)
                } else {
                    DispatchQueue.main.async { completion(media) }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { completion(media) }
        @unknown default:
            DispatchQueue.main.async { completion(media) }
        }
    }

    private func performSave(media: [PickedMedia], completion: @escaping ([PickedMedia]) -> Void) {
        var savedMedia: [PickedMedia] = []
        let group = DispatchGroup()

        for item in media {
            group.enter()

            switch item {
            case let .video(url, duration, assetIdentifier):
                guard let url else {
                    TapesLog.camera.error("Missing video URL for captured media")
                    group.leave()
                    continue
                }
                var placeholderId: String?
                PHPhotoLibrary.shared().performChanges({
                    if let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) {
                        placeholderId = request.placeholderForCreatedAsset?.localIdentifier
                    }
                }) { success, error in
                    if !success {
                        TapesLog.camera.error("Failed to save video \(url.lastPathComponent): \(error?.localizedDescription ?? "Unknown error")")
                    } else {
                        let savedDuration = duration > 0 ? duration : self.durationFromPhotos(localIdentifier: placeholderId ?? assetIdentifier)
                        let savedItem = PickedMedia.video(url: url, duration: savedDuration, assetIdentifier: placeholderId ?? assetIdentifier)
                        savedMedia.append(savedItem)
                    }
                    group.leave()
                }
                continue
            case let .photo(image, assetIdentifier, _):
                var placeholderId: String?
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                    placeholderId = request.placeholderForCreatedAsset?.localIdentifier
                }) { success, error in
                    if success {
                        let savedItem = PickedMedia.photo(image: image, assetIdentifier: placeholderId ?? assetIdentifier)
                        savedMedia.append(savedItem)
                    } else {
                        TapesLog.camera.error("Failed to save photo: \(error?.localizedDescription ?? "Unknown error")")
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            completion(savedMedia)
        }
    }

    private func durationFromPhotos(localIdentifier: String?) -> TimeInterval {
        guard let localIdentifier else { return 0 }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return 0 }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        return fetch.firstObject?.duration ?? 0
    }
}
