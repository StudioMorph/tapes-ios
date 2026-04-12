import SwiftUI

struct MainTabView: View {
    @Binding var showOnboarding: Bool
    @State private var selectedTab: AppTab = .myTapes

    enum AppTab: Hashable {
        case myTapes
        case shared
        case account
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("My Tapes", systemImage: "film.stack", value: AppTab.myTapes) {
                TapesListView()
            }

            Tab("Shared", systemImage: "person.2", value: AppTab.shared) {
                SharedTapesView()
            }

            Tab("Account", systemImage: "person.circle", value: AppTab.account) {
                AccountTabView(showOnboarding: $showOnboarding)
            }
        }
        .tint(Tokens.Colors.systemBlue)
    }
}

#Preview {
    MainTabView(showOnboarding: .constant(false))
        .environmentObject(TapesStore())
        .environmentObject(AuthManager())
        .environmentObject(EntitlementManager())
}
