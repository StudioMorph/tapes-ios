import UIKit
import AppTrackingTransparency
import UserMessagingPlatform
import os

@MainActor
final class ConsentManager: ObservableObject {

    static let shared = ConsentManager()

    @Published private(set) var canRequestAds = false

    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "Consent")

    private init() {}

    /// Runs the full consent chain: UMP update → consent form → ATT prompt.
    /// Call once at app launch from the root view controller.
    func requestConsentIfNeeded(from viewController: UIViewController) {
        let parameters = UMPRequestParameters()

        #if DEBUG
        let debugSettings = UMPDebugSettings()
        debugSettings.geography = .EEA
        parameters.debugSettings = debugSettings
        #endif

        UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: parameters) { [weak self] error in
            guard let self else { return }

            if let error {
                self.log.error("UMP consent info update failed: \(error.localizedDescription)")
                Task { @MainActor in
                    await self.requestATTIfNeeded()
                    self.canRequestAds = true
                }
                return
            }

            Task { @MainActor in
                do {
                    try await UMPConsentForm.loadAndPresentIfRequired(from: viewController)
                    self.log.info("UMP consent form handled")
                } catch {
                    self.log.error("UMP consent form error: \(error.localizedDescription)")
                }

                await self.requestATTIfNeeded()
                self.canRequestAds = UMPConsentInformation.sharedInstance.canRequestAds
                self.log.info("Consent resolved — canRequestAds: \(self.canRequestAds)")
            }
        }
    }

    /// Whether the user should see a "Privacy Settings" button in Preferences.
    var shouldShowPrivacySettings: Bool {
        UMPConsentInformation.sharedInstance.privacyOptionsRequirementStatus == .required
    }

    /// Re-presents the UMP privacy options form.
    func presentPrivacyOptions(from viewController: UIViewController) async {
        do {
            try await UMPConsentForm.presentPrivacyOptionsForm(from: viewController)
        } catch {
            log.error("Privacy options form error: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func requestATTIfNeeded() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }

        let status = await ATTrackingManager.requestTrackingAuthorization()
        switch status {
        case .authorized:
            log.info("ATT authorised")
        case .denied:
            log.info("ATT denied — serving non-personalised ads")
        case .restricted:
            log.info("ATT restricted")
        case .notDetermined:
            log.info("ATT not determined")
        @unknown default:
            break
        }
    }
}
