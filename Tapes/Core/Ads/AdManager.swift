import GoogleMobileAds
import os

@MainActor
final class AdManager: NSObject, ObservableObject {

    static let shared = AdManager()

    @Published private(set) var isAdPlaying = false

    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "Ads")

    private var interstitialAd: GADInterstitialAd?
    private var adCompletion: ((Bool) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - Lifecycle

    /// Call once at app launch to initialise the Google Mobile Ads SDK
    /// and begin preloading the first interstitial.
    func start() {
        GADMobileAds.sharedInstance().start { [weak self] _ in
            self?.log.info("Google Mobile Ads SDK initialised")
        }
        Task { await loadAd() }
    }

    // MARK: - Loading

    /// Preloads an interstitial ad so it's ready when needed.
    /// Ads expire after one hour; the SDK handles cache invalidation.
    private func loadAd() async {
        do {
            interstitialAd = try await GADInterstitialAd.load(
                withAdUnitID: AdConfig.interstitialAdUnitID,
                request: GADRequest()
            )
            interstitialAd?.fullScreenContentDelegate = self
            log.info("Interstitial ad loaded")
        } catch {
            log.error("Interstitial ad load failed: \(error.localizedDescription)")
            interstitialAd = nil
        }
    }

    // MARK: - Presentation

    /// Shows a preloaded interstitial ad. Returns `true` if the ad was
    /// presented and dismissed normally, `false` if no ad was available
    /// or presentation failed.
    func showAd() async -> Bool {
        guard let ad = interstitialAd else {
            log.warning("No interstitial ready — skipping ad slot")
            return false
        }

        return await withCheckedContinuation { continuation in
            adCompletion = { success in
                continuation.resume(returning: success)
            }
            isAdPlaying = true
            ad.present(fromRootViewController: nil)
        }
    }

    /// Clean up any pending state. Call when the player is dismissed.
    func tearDown() {
        isAdPlaying = false
        interstitialAd = nil

        let pending = adCompletion
        adCompletion = nil
        pending?(false)
    }
}

// MARK: - GADFullScreenContentDelegate

extension AdManager: GADFullScreenContentDelegate {

    nonisolated func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        Task { @MainActor in
            log.info("Interstitial dismissed")
            isAdPlaying = false
            let completion = adCompletion
            adCompletion = nil
            interstitialAd = nil
            completion?(true)
            await loadAd()
        }
    }

    nonisolated func ad(
        _ ad: GADFullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        Task { @MainActor in
            log.error("Interstitial present failed: \(error.localizedDescription)")
            isAdPlaying = false
            let completion = adCompletion
            adCompletion = nil
            interstitialAd = nil
            completion?(false)
            await loadAd()
        }
    }

    nonisolated func adWillPresentFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        Task { @MainActor in
            log.info("Interstitial will present")
        }
    }

    nonisolated func adDidRecordImpression(_ ad: GADFullScreenPresentingAd) {
        Task { @MainActor in
            log.info("Interstitial impression recorded")
        }
    }

    nonisolated func adDidRecordClick(_ ad: GADFullScreenPresentingAd) {
        Task { @MainActor in
            log.info("Interstitial click recorded")
        }
    }
}
