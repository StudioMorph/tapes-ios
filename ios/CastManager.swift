import Foundation
import AVKit
import Combine

/// AirPlay discovery (MVP): polls every 10s.
final class CastManager: ObservableObject {
    static let shared = CastManager()
    @Published private(set) var hasAvailableDevices: Bool = false
    private let detector = AVRouteDetector()
    private var timer: Timer?
    private init() {
        detector.isRouteDetectionEnabled = true
        startPolling()
    }
    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.hasAvailableDevices = self?.detector.multipleRoutesDetected ?? false
        }
        hasAvailableDevices = detector.multipleRoutesDetected
    }
}
