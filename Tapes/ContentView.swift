//
//  ContentView.swift
//  Tapes
//
//  Created by Jose Santos on 25/09/2025.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @AppStorage("tapes_onboarding_completed") private var onboardingCompleted = false
    @AppStorage("tapes_hot_tips_remaining") private var hotTipsRemaining = 5
    @State private var showOnboarding = false

    var body: some View {
        TapesListView(showOnboarding: $showOnboarding)
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
    }
}

#Preview {
    ContentView()
        .environmentObject(TapesStore())
        .environmentObject(EntitlementManager())
}
