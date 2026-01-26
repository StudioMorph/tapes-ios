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
        
        // Check camera permission
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
            // Handle permission denied
            break
        @unknown default:
            break
        }
    }
    
    func handleCapturedMedia(_ media: [PickedMedia]) {
        self.capturedMedia = media
        
        // Save media to Photos library
        saveMediaToPhotosLibrary(media) { [weak self] savedMedia in
            DispatchQueue.main.async {
                self?.completion?(savedMedia)
                self?.isPresented = false
            }
        }
    }
    
    private func saveMediaToPhotosLibrary(_ media: [PickedMedia], completion: @escaping ([PickedMedia]) -> Void) {
        guard !media.isEmpty else {
            completion([])
            return
        }
        
        // Check Photos permission
        let status = PHPhotoLibrary.authorizationStatus()
        
        switch status {
        case .authorized, .limited:
            performSave(media: media, completion: completion)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { newStatus in
                if newStatus == .authorized || newStatus == .limited {
                    self.performSave(media: media, completion: completion)
                } else {
                    // Permission denied, return original media without saving
                    DispatchQueue.main.async {
                        completion(media)
                    }
                }
            }
        case .denied, .restricted:
            // Permission denied, return original media without saving
            DispatchQueue.main.async {
                completion(media)
            }
        @unknown default:
            DispatchQueue.main.async {
                completion(media)
            }
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
            case let .photo(image, assetIdentifier):
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

struct CameraView: UIViewControllerRepresentable {
    @ObservedObject var coordinator: CameraCoordinator
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.mediaTypes = ["public.movie", "public.image"] // Allow both video and photo
        picker.videoQuality = .typeHigh
        picker.allowsEditing = false
        picker.cameraCaptureMode = .video // Set video as default
        picker.modalPresentationStyle = .fullScreen // Ensure full screen presentation
        picker.modalTransitionStyle = .coverVertical // Standard camera transition
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // Ensure the picker maintains full screen presentation
        uiViewController.modalPresentationStyle = .fullScreen
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(coordinator: coordinator)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let coordinator: CameraCoordinator
        
        init(coordinator: CameraCoordinator) {
            self.coordinator = coordinator
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            var mediaItems: [PickedMedia] = []
            
            if let videoURL = info[.mediaURL] as? URL {
                // Handle video capture; duration resolved after save
                mediaItems.append(.video(url: videoURL, duration: 0, assetIdentifier: nil))
            } else if let image = info[.originalImage] as? UIImage {
                // Handle photo capture
                mediaItems.append(.photo(image: image, assetIdentifier: nil))
            }
            
            picker.dismiss(animated: true) {
                self.coordinator.handleCapturedMedia(mediaItems)
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) {
                self.coordinator.isPresented = false
            }
        }
    }

}
