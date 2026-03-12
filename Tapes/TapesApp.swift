//
//  TapesApp.swift
//  Tapes
//
//  Created by Jose Santos on 25/09/2025.
//

import SwiftUI

@main
struct TapesApp: App {
    @StateObject private var tapeStore = TapesStore()
    @StateObject private var authManager = AuthManager()
    @StateObject private var entitlementManager = EntitlementManager()

    init() {
        cleanupTempImports()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tapeStore)
                .environmentObject(authManager)
                .environmentObject(entitlementManager)
        }
    }
}
