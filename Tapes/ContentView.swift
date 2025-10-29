//
//  ContentView.swift
//  Tapes
//
//  Created by Jose Santos on 25/09/2025.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TapesListView()
            .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
    }
}

#Preview {
    ContentView()
        .environmentObject(TapesStore())  // lightweight preview store
}
