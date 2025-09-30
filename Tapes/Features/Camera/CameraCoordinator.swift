import SwiftUI
import UIKit
import AVFoundation

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
        self.completion?(media)
        self.isPresented = false
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
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // No updates needed
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
                // Handle video capture
                mediaItems.append(.video(videoURL))
            } else if let image = info[.originalImage] as? UIImage {
                // Handle photo capture
                mediaItems.append(.photo(image))
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
