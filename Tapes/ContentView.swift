//
//  ContentView.swift
//  Tapes
//
//  Created by Jose Santos on 25/09/2025.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    @AppStorage("tapes_onboarding_completed") private var onboardingCompleted = false
    @AppStorage("tapes_hot_tips_remaining") private var hotTipsRemaining = 5
    @State private var showOnboarding = false

    var body: some View {
        Group {
            if authManager.isSignedIn {
                MainTabView(showOnboarding: $showOnboarding)
                    .onAppear {
                        entitlementManager.refresh()
                        if !onboardingCompleted {
                            showOnboarding = true
                        }
                    }
                    .fullScreenCover(isPresented: $showOnboarding) {
                        OnboardingView(isReopen: onboardingCompleted) {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                showOnboarding = false
                            }
                        }
                        .presentationBackground(.clear)
                    }
            } else {
                // Reset-password tokens arrive via deep link and live on the
                // navigation coordinator so the single top-level `.onOpenURL`
                // in TapesApp can write them. AuthView consumes via binding.
                AuthView(resetPasswordToken: Binding(
                    get: { navigationCoordinator.pendingResetToken },
                    set: { navigationCoordinator.pendingResetToken = $0 }
                ))
            }
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

#Preview {
    ContentView()
        .environmentObject(TapesStore())
        .environmentObject(AuthManager())
        .environmentObject(EntitlementManager())
}
