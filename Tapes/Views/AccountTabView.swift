import SwiftUI

struct AccountTabView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @Binding var showOnboarding: Bool
    @State private var showingPaywall = false
    @State private var showingDeleteAccount = false

    private var isSignedIn: Bool {
        authManager.isSignedIn
    }

    private var tierDisplayName: String {
        switch entitlementManager.accessLevel {
        case .free: return "Tapes Free"
        case .plus: return "Tapes Plus"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                accountSection.listRowBackground(Tokens.Colors.secondaryBackground)
                settingsSection.listRowBackground(Tokens.Colors.secondaryBackground)
                hotTipsSection.listRowBackground(Tokens.Colors.secondaryBackground)

                if isSignedIn {
                    signOutAndDeleteButtons
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.large)
            .alert("Sign In Issue", isPresented: .init(
                get: { authManager.authError != nil },
                set: { if !$0 { authManager.authError = nil } }
            )) {
                Button("OK") { authManager.authError = nil }
            } message: {
                if let msg = authManager.authError {
                    Text(msg)
                }
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showingDeleteAccount) {
            DeleteAccountSheet()
        }
    }

    // MARK: - Account

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if let name = authManager.userName {
                LabeledContent("Name", value: name)
            }
            if let email = authManager.userEmail {
                LabeledContent("Email", value: email)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Email Status")
                    Spacer()
                    Text(authManager.isEmailVerified ? "Verified" : "Not Verified")
                        .foregroundStyle(authManager.isEmailVerified ? .green : .orange)
                }
                if !authManager.isEmailVerified {
                    HStack {
                        Spacer()
                        Button {
                            Task { await authManager.resendVerification() }
                        } label: {
                            Text("Resend Email")
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            LabeledContent("Plan", value: tierDisplayName)

            if entitlementManager.isPremium {
                Button("Manage Subscription") {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                }
            } else {
                Button("Upgrade to Tapes Plus") {
                    showingPaywall = true
                }
            }
        } header: {
            Text("Account")
                .font(Tokens.Typography.title)
                .foregroundStyle(Tokens.Colors.primaryText)
                .textCase(nil)
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        Section {
            NavigationLink {
                PreferencesView()
            } label: {
                Label("Preferences", systemImage: "slider.horizontal.3")
            }

            NavigationLink {
                AppInfoView()
            } label: {
                Label("App Info", systemImage: "info.circle")
            }
        } header: {
            Text("Settings")
                .font(Tokens.Typography.title)
                .foregroundStyle(Tokens.Colors.primaryText)
                .textCase(nil)
        }
    }

    // MARK: - Hot Tips

    private var hotTipsSection: some View {
        Section {
            Button {
                showOnboarding = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "lightbulb.max")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    Text("Hot Tips")
                        .foregroundStyle(Tokens.Colors.primaryText)
                }
            }
        }
    }

    // MARK: - Sign Out & Delete

    @ViewBuilder
    private var signOutAndDeleteButtons: some View {
        Section {
            VStack(spacing: Tokens.Spacing.xl) {
                Button {
                    authManager.signOut()
                } label: {
                    Text("Sign Out")
                        .frame(maxWidth: .infinity, minHeight: Tokens.HitTarget.minimum)
                }
                .buttonStyle(.bordered)

                Button {
                    showingDeleteAccount = true
                } label: {
                    Label("Delete Account & Data", systemImage: "trash")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .frame(minHeight: Tokens.HitTarget.minimum)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: Tokens.Spacing.m, leading: 0, bottom: Tokens.Spacing.m, trailing: 0))
        }
    }
}

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
}

#Preview {
    AccountTabView(showOnboarding: .constant(false))
        .environmentObject(AuthManager())
        .environmentObject(EntitlementManager())
}
