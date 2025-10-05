import SwiftUI
import PhotosUI
import UIKit

// MARK: - SystemMediaPicker

struct SystemMediaPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let allowImages: Bool
    let allowVideos: Bool
    let onPicked: (_ orderedItems: [PHPickerResult]) -> Void

    func makeCoordinator() -> Coordinator { 
        Coordinator(self) 
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 0                 // multi-select
        config.selection = .ordered               // preserve selection order
        config.filter = .any(of: [.images, .videos])  // both images and videos
        config.preferredAssetRepresentationMode = .current   // avoid iCloud originals

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator     // ✅ hook delegate
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: SystemMediaPicker
        init(_ parent: SystemMediaPicker) { 
            self.parent = parent 
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            TapesLog.mediaPicker.info("PHPicker didFinishPicking — results.count = \(results.count)")
            parent.isPresented = false
            // Hand back to SwiftUI
            parent.onPicked(results)
        }
    }
}

// MARK: - MediaPickerSheet (Legacy - keeping for compatibility)

enum MediaFilter: String, CaseIterable {
    case videos = "Videos"
    case photos = "Photos"
    case collections = "Collections"
}

struct MediaPickerSheet: View {
    @Binding var isPresented: Bool
    @State private var filter: MediaFilter = .videos
    @State private var results: [PHPickerResult] = []
    let onComplete: ([PHPickerResult]) -> Void
    let onClear: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            Divider()
            
            // PHPicker Container
            PHPickerContainer(filter: filter, selection: $results)
                .background(Color(uiColor: .systemBackground))
        }
        .presentationDetents([.large])
        .presentationBackground(.regularMaterial)
    }
    
    private var header: some View {
        HStack {
            // Clear button
            Button("Clear") {
                results = []
                onClear()
            }
            .foregroundColor(Tokens.Colors.red)
            
            Spacer()
            
            // Segmented control
            Picker("Filter", selection: $filter) {
                ForEach(MediaFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: 200)
            
            Spacer()
            
            // Done button
            Button("Done") {
                onComplete(results)
                isPresented = false
            }
            .foregroundColor(Tokens.Colors.red)
            .fontWeight(.semibold)
        }
        .padding(.horizontal, Tokens.Spacing.m)
        .padding(.vertical, Tokens.Spacing.s)
    }
}

// MARK: - PHPickerContainer

struct PHPickerContainer: UIViewControllerRepresentable {
    var filter: MediaFilter
    @Binding var selection: [PHPickerResult]
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        let picker = PHPickerViewController(configuration: makeConfig())
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {
        // Update configuration if filter changed
        let newConfig = makeConfig()
        if vc.configuration.filter != newConfig.filter {
            // Recreate the picker with new configuration
            let newPicker = PHPickerViewController(configuration: newConfig)
            newPicker.delegate = context.coordinator
            
            // Present the new picker
            vc.present(newPicker, animated: true)
        }
    }
    
    private func makeConfig() -> PHPickerConfiguration {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 0 // Multi-select
        config.selection = .ordered // Preserve selection order
        config.preferredAssetRepresentationMode = .current
        
        // Set filter based on current selection
        switch filter {
        case .videos:
            config.filter = .videos
        case .photos:
            config.filter = .images
        case .collections:
            config.filter = .any(of: [.images, .videos])
        }
        
        return config
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }
    
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        @Binding var selection: [PHPickerResult]
        
        init(selection: Binding<[PHPickerResult]>) {
            self._selection = selection
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            selection = results // Preserves order
        }
    }
}

// MARK: - Preview

#Preview {
    MediaPickerSheet(
        isPresented: .constant(true),
        onComplete: { _ in },
        onClear: { }
    )
}
