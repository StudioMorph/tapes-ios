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
    @AppStorage("tapes_onboarding_completed") private var onboardingCompleted = false
    @AppStorage("tapes_hot_tips_remaining") private var hotTipsRemaining = 5
    @State private var showOnboarding = false
    @State private var resetPasswordToken: String?

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
                AuthView(resetPasswordToken: $resetPasswordToken)
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    private func handleDeepLink(_ url: URL) {
        if url.scheme == "tapes" && url.host == "verified" {
            authManager.markEmailVerified()
            return
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           components.path.contains("reset-password"),
           let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
            resetPasswordToken = token
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
