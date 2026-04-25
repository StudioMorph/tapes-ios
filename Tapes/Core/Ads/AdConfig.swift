import Foundation

enum AdConfig {

    /// Duration (in seconds) between mid-roll ad breaks.
    static let midRollInterval: TimeInterval = 300

    /// Duration (in seconds) of the offline fallback countdown.
    static let offlineCountdownDuration: Int = 10

    /// Base VAST ad tag URL. Swap this single value when transitioning
    /// from Google's sample tag to a live Ad Manager unit.
    ///
    /// Production format: `/XXXXXXXX/tapes_video_preroll`
    private static let adTagBase = "https://pubads.g.doubleclick.net/gampad/ads?iu=/21775744923/external/single_ad_samples&sz=640x480&cust_params=sample_ct%3Dlinear&ciu_szs=300x250%2C728x90&gdfp_req=1&output=vast&unviewed_position_start=1&env=vp&impl=s&correlator="

    /// Returns an ad tag URL with a unique correlator for each request,
    /// ensuring the ad server treats every call as a fresh impression.
    static var adTagURL: String {
        adTagBase + "\(Int(Date().timeIntervalSince1970 * 1000))"
    }
}
