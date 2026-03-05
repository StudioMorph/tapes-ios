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
    }
}

#Preview {
    ContentView()
        .environmentObject(TapesStore())  // lightweight preview store
}
