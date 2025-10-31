//
//  TapesApp.swift
//  Tapes
//
//  Created by Jose Santos on 25/09/2025.
//

import SwiftUI

@main
struct TapesApp: App {
    @StateObject private var tapeStore = TapesStore()   // single source of truth

    init() {
        // Clean up stale cache files on app startup to prevent AVFoundation errors
        Task.detached(priority: .utility) {
            TapeCompositionBuilder.cleanupStaleCache()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tapeStore)          // <- provide to whole tree
        }
    }
}
