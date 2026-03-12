//
//  TrialManager.swift
//  Tapes
//
//  Created by AI Assistant on 26/01/2026.
//

import Foundation
import SwiftUI

@MainActor
final class TrialManager: ObservableObject {

    // MARK: - Constants

    static let maxFreeTapes = 3
    private static let freeDays = 3
    private static let installDateKey = "tapes_install_date"

    // MARK: - Published State

    @Published private(set) var trialState: TrialState = .active

    enum TrialState: Equatable {
        case active
        case expired
    }

    // MARK: - Lifecycle

    init() {
        ensureInstallDate()
        refreshTrialState()
    }

    // MARK: - Install Date

    var installDate: Date {
        guard let date = UserDefaults.standard.object(forKey: Self.installDateKey) as? Date else {
            let now = Date()
            UserDefaults.standard.set(now, forKey: Self.installDateKey)
            return now
        }
        return date
    }

    private func ensureInstallDate() {
        if UserDefaults.standard.object(forKey: Self.installDateKey) == nil {
            UserDefaults.standard.set(Date(), forKey: Self.installDateKey)
        }
    }

    // MARK: - Trial State

    var trialExpiryDate: Date {
        Calendar.current.date(byAdding: .day, value: Self.freeDays, to: installDate) ?? installDate
    }

    var daysRemaining: Int {
        let remaining = Calendar.current.dateComponents([.day], from: Date(), to: trialExpiryDate).day ?? 0
        return max(0, remaining)
    }

    var isTrialActive: Bool {
        trialState == .active
    }

    var isTrialExpired: Bool {
        trialState == .expired
    }

    func refreshTrialState() {
        trialState = Date() < trialExpiryDate ? .active : .expired
    }

    // MARK: - Tape Limit

    func canCreateTape(currentCount: Int) -> Bool {
        currentCount < Self.maxFreeTapes
    }

    func tapeLimitReached(currentCount: Int) -> Bool {
        currentCount >= Self.maxFreeTapes
    }

    // MARK: - Reset (for testing)

    #if DEBUG
    func resetTrial() {
        UserDefaults.standard.removeObject(forKey: Self.installDateKey)
        ensureInstallDate()
        refreshTrialState()
    }
    #endif
}
