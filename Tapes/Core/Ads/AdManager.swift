import GoogleMobileAds
import os

@MainActor
final class AdManager: NSObject, ObservableObject {

    static let shared = AdManager()

    @Published private(set) var isAdPlaying = false

    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "Ads")

    private var interstitialAd: GADInterstitialAd?
    private var adCompletion: ((Bool) -> Void)?
    private var isLoading = false
    private var isPresenting = false

    private override init() {
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        #if DEBUG
        GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = [
            "83e998c22f64a2ce669658ab1f727a12"
        ]
        #endif

        GADMobileAds.sharedInstance().start { [weak self] _ in
            self?.log.info("Google Mobile Ads SDK initialised")
        }
        Task { await loadAd() }
    }

    // MARK: - Loading

    private func loadAd() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

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

    func showAd() async -> Bool {
        guard !isPresenting else {
            log.info("Ad already presenting — skipping duplicate call")
            return false
        }

        if interstitialAd == nil && isLoading {
            log.info("Ad still loading — waiting up to 4s")
            for _ in 0..<8 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if interstitialAd != nil { break }
            }
        }

        guard let ad = interstitialAd else {
            log.warning("No interstitial ready — skipping ad slot")
            Task { await loadAd() }
            return false
        }

        interstitialAd = nil
        isPresenting = true

        return await withCheckedContinuation { continuation in
            adCompletion = { success in
                continuation.resume(returning: success)
            }
            isAdPlaying = true
            ad.present(fromRootViewController: nil)
        }
    }

    /// Clean up in-flight presentation state only. Does not destroy
    /// preloaded ads so the next playback can use them.
    func tearDown() {
        isAdPlaying = false
        isPresenting = false

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
            isPresenting = false
            let completion = adCompletion
            adCompletion = nil
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
            isPresenting = false
            let completion = adCompletion
            adCompletion = nil
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
