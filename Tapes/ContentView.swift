//
//  ContentView.swift
//  Tapes
//
//  Created by Jose Santos on 25/09/2025.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var entitlementManager: EntitlementManager

    var body: some View {
        TapesListView()
            .onAppear {
                entitlementManager.refresh()
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(TapesStore())
        .environmentObject(EntitlementManager())
}
