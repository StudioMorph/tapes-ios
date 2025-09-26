import SwiftUI
import PhotosUI
import AVFoundation

struct PHPickerVideo: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onVideoSelected: (URL, Double, UIImage?) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .videos
        configuration.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PHPickerVideo
        
        init(_ parent: PHPickerVideo) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let result = results.first else {
                parent.isPresented = false
                return
            }
            
            // Load the video asset using loadFileRepresentation
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.movie") { [weak self] url, error in
                guard let self = self,
                      let url = url,
                      error == nil else {
                    DispatchQueue.main.async {
                        self?.parent.isPresented = false
                    }
                    return
                }
                
                // Create AVAsset from the URL
                let asset = AVAsset(url: url)
                self.processVideo(asset: asset, originalURL: url)
            }
        }
        
        private func processVideo(asset: AVAsset, originalURL: URL) {
            // Get duration
            let duration = CMTimeGetSeconds(asset.duration)
            
            // Generate thumbnail
            let thumbnail = generateThumbnail(from: asset)
            
            // Copy to temp directory
            guard let tempURL = copyToTemp(originalURL: originalURL) else {
                DispatchQueue.main.async {
                    self.parent.isPresented = false
                }
                return
            }
            
            DispatchQueue.main.async {
                self.parent.onVideoSelected(tempURL, duration, thumbnail)
                self.parent.isPresented = false
            }
        }
        
        private func generateThumbnail(from asset: AVAsset) -> UIImage? {
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 320, height: 320)
            
            let time = CMTime(seconds: 1.0, preferredTimescale: 60)
            
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                return UIImage(cgImage: cgImage)
            } catch {
                return nil
            }
        }
        
        private func copyToTemp(originalURL: URL) -> URL? {
            let tempDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let tapesDir = tempDir.appendingPathComponent("TapesTemp")
            
            // Create directory if needed
            try? FileManager.default.createDirectory(at: tapesDir, withIntermediateDirectories: true)
            
            let fileName = UUID().uuidString + ".mp4"
            let outputURL = tapesDir.appendingPathComponent(fileName)
            
            do {
                try FileManager.default.copyItem(at: originalURL, to: outputURL)
                return outputURL
            } catch {
                print("Failed to copy video to temp directory: \(error)")
                return nil
            }
        }
    }
}
