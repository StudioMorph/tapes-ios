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
        // Use background priority and delay slightly to avoid blocking startup
        Task.detached(priority: .background) {
            // Small delay to let UI render first
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
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
