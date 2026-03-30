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

    var body: some View {
        if onboardingCompleted {
            TapesListView()
                .onAppear {
                    entitlementManager.refresh()
                }
        } else {
            OnboardingView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(TapesStore())
        .environmentObject(EntitlementManager())
}
