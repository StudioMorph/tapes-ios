import UIKit
import AVFoundation
import GoogleInteractiveMediaAds
import os

@MainActor
final class AdManager: NSObject, ObservableObject {

    static let shared = AdManager()

    @Published private(set) var isAdPlaying = false
    private(set) var userClickedAd = false

    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "Ads")

    private var adsLoader: IMAAdsLoader?
    private var adsManager: IMAAdsManager?
    private var adDisplayContainer: IMAAdDisplayContainer?
    private var contentPlayhead: IMAAVPlayerContentPlayhead?

    private var adCompletion: ((Bool) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - Lifecycle

    /// Call once at app launch to initialise the IMA ads loader.
    func preWarm() {
        guard adsLoader == nil else { return }

        let settings = IMASettings()
        settings.sameAppKeyEnabled = true

        adsLoader = IMAAdsLoader(settings: settings)
        adsLoader?.delegate = self
        log.info("IMA SDK pre-warmed")
    }

    /// Request and play a single ad in the given container view.
    ///
    /// - Parameters:
    ///   - containerView: The UIView that will host the ad.
    ///   - viewController: The UIViewController presenting the ad.
    ///   - contentPlayer: The content AVPlayer (used for playhead tracking).
    /// - Returns: `true` if an ad played successfully, `false` if it was skipped.
    func requestAndPlayAd(
        in containerView: UIView,
        viewController: UIViewController,
        contentPlayer: AVPlayer
    ) async -> Bool {
        guard let adsLoader else {
            log.warning("Ads loader not initialised — skipping ad")
            return false
        }

        tearDownCurrentAd()

        let playhead = IMAAVPlayerContentPlayhead(avPlayer: contentPlayer)
        contentPlayhead = playhead

        let displayContainer = IMAAdDisplayContainer(
            adContainer: containerView,
            viewController: viewController
        )
        adDisplayContainer = displayContainer

        let request = IMAAdsRequest(
            adTagUrl: AdConfig.adTagURL,
            adDisplayContainer: displayContainer,
            contentPlayhead: playhead,
            userContext: nil
        )

        return await withCheckedContinuation { continuation in
            adCompletion = { success in
                continuation.resume(returning: success)
            }
            adsLoader.requestAds(with: request)
            log.info("Ad request sent")
        }
    }

    /// Clean up the current ad manager. Call when the player is dismissed.
    func tearDownCurrentAd() {
        adsManager?.destroy()
        adsManager = nil
        adDisplayContainer = nil
        contentPlayhead = nil
        isAdPlaying = false
        userClickedAd = false
        adsLoader?.contentComplete()
    }

    /// Call when returning from background after a CTA click.
    /// Completes the ad early so the tape plays immediately.
    func completeAdAfterClick() {
        guard userClickedAd else { return }
        log.info("Completing ad after CTA return")
        isAdPlaying = false
        let completion = adCompletion
        adCompletion = nil
        tearDownCurrentAd()
        completion?(true)
    }
}

// MARK: - IMAAdsLoaderDelegate

extension AdManager: IMAAdsLoaderDelegate {

    nonisolated func adsLoader(_ loader: IMAAdsLoader, adsLoadedWith adsLoadedData: IMAAdsLoadedData) {
        Task { @MainActor in
            let manager = adsLoadedData.adsManager
            manager?.delegate = self
            adsManager = manager

            let renderingSettings = IMAAdsRenderingSettings()
            renderingSettings.enablePreloading = true

            manager?.initialize(with: renderingSettings)
            log.info("Ads manager initialised")
        }
    }

    nonisolated func adsLoader(_ loader: IMAAdsLoader, failedWith adErrorData: IMAAdLoadingErrorData) {
        Task { @MainActor in
            log.error("Ad load failed: \(adErrorData.adError.message ?? "unknown")")
            adCompletion?(false)
            adCompletion = nil
        }
    }
}

// MARK: - IMAAdsManagerDelegate

extension AdManager: IMAAdsManagerDelegate {

    nonisolated func adsManager(_ adsManager: IMAAdsManager, didReceive event: IMAAdEvent) {
        Task { @MainActor in
            switch event.type {
            case .LOADED:
                adsManager.start()
                log.info("Ad loaded — starting playback")

            case .STARTED:
                isAdPlaying = true
                log.info("Ad started")

            case .CLICKED:
                userClickedAd = true
                log.info("Ad clicked — will skip remainder on return")

            case .COMPLETE:
                isAdPlaying = false
                log.info("Ad completed")
                adCompletion?(true)
                adCompletion = nil

            case .ALL_ADS_COMPLETED:
                tearDownCurrentAd()

            default:
                break
            }
        }
    }

    nonisolated func adsManager(_ adsManager: IMAAdsManager, didReceive error: IMAAdError) {
        Task { @MainActor in
            log.error("Ad playback error: \(error.message ?? "unknown")")
            isAdPlaying = false
            adCompletion?(false)
            adCompletion = nil
            tearDownCurrentAd()
        }
    }

    nonisolated func adsManagerDidRequestContentPause(_ adsManager: IMAAdsManager) {
        Task { @MainActor in
            isAdPlaying = true
        }
    }

    nonisolated func adsManagerDidRequestContentResume(_ adsManager: IMAAdsManager) {
        Task { @MainActor in
            isAdPlaying = false
        }
    }
}
