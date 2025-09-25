import SwiftUI
import AVKit

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.prioritizesVideoDevices = true
        v.activeTintColor = UIColor.systemRed
        v.tintColor = UIColor.white
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
