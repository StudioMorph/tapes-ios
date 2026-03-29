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
    @State private var showPaywall = false

    private static let postAuthPaywallShownKey = "tapes_post_auth_paywall_shown"

    var body: some View {
        Group {
            if !authManager.isSignedIn {
                SignInView()
            } else {
                mainAppView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authManager.isSignedIn)
    }

    @ViewBuilder
    private var mainAppView: some View {
        TapesListView()
            .onAppear {
                entitlementManager.refresh()
                guard authManager.didSignInThisSession else { return }
                if !entitlementManager.isPremium {
                    let alreadyShown = UserDefaults.standard.bool(forKey: Self.postAuthPaywallShownKey)
                    if !alreadyShown {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showPaywall = true
                            UserDefaults.standard.set(true, forKey: Self.postAuthPaywallShownKey)
                        }
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(TapesStore())
        .environmentObject(AuthManager())
        .environmentObject(EntitlementManager())
}
