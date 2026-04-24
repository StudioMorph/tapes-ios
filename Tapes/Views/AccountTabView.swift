import SwiftUI

struct AccountTabView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @Binding var showOnboarding: Bool

    @AppStorage("tapes_appearance_mode") private var appearanceMode: AppearanceMode = .system

    private var isSignedIn: Bool {
        authManager.isSignedIn
    }

    private var tierDisplayName: String {
        switch entitlementManager.accessLevel {
        case .free:     return "Free"
        case .plus:     return "Plus"
        case .together: return "Together"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                accountSection.listRowBackground(Tokens.Colors.secondaryBackground)
                appearanceSection.listRowBackground(Tokens.Colors.secondaryBackground)
                hotTipsSection.listRowBackground(Tokens.Colors.secondaryBackground)
                aboutSection.listRowBackground(Tokens.Colors.secondaryBackground)
                creditsSection.listRowBackground(Tokens.Colors.secondaryBackground)
                legalSection.listRowBackground(Tokens.Colors.secondaryBackground)

                if isSignedIn {
                    signOutSection.listRowBackground(Tokens.Colors.secondaryBackground)
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
    }

    // MARK: - Account

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if let name = authManager.userName {
                HStack {
                    Text("Name")
                        .foregroundColor(Tokens.Colors.primaryText)
                    Spacer()
                    Text(name)
                        .foregroundColor(Tokens.Colors.secondaryText)
                }
            }
            if let email = authManager.userEmail {
                HStack {
                    Text("Email")
                        .foregroundColor(Tokens.Colors.primaryText)
                    Spacer()
                    Text(email)
                        .foregroundColor(Tokens.Colors.secondaryText)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Email Status")
                        .foregroundColor(Tokens.Colors.primaryText)
                    Spacer()
                    Text(authManager.isEmailVerified ? "Verified" : "Not Verified")
                        .foregroundColor(authManager.isEmailVerified ? .green : .orange)
                }
                if !authManager.isEmailVerified {
                    HStack {
                        Spacer()
                        Button {
                            Task { await authManager.resendVerification() }
                        } label: {
                            Text("Resend Email")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Text("Plan")
                    .foregroundColor(Tokens.Colors.primaryText)
                Spacer()
                Text(tierDisplayName)
                    .foregroundColor(Tokens.Colors.secondaryText)
            }

            if !entitlementManager.isPremium {
                Button("Manage Subscription") {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } header: {
            Text("Account")
                .font(Tokens.Typography.title)
                .foregroundColor(Tokens.Colors.primaryText)
                .textCase(nil)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Appearance")
                .font(Tokens.Typography.title)
                .foregroundColor(Tokens.Colors.primaryText)
                .textCase(nil)
        } footer: {
            Text("Choose how Tapes looks. System follows your device settings.")
                .foregroundColor(Tokens.Colors.secondaryText)
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
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    Text("Hot Tips")
                        .foregroundColor(Tokens.Colors.primaryText)
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                    .foregroundColor(Tokens.Colors.primaryText)
                Spacer()
                Text(appVersion)
                    .foregroundColor(Tokens.Colors.secondaryText)
            }

            HStack {
                Text("Build")
                    .foregroundColor(Tokens.Colors.primaryText)
                Spacer()
                Text(appBuild)
                    .foregroundColor(Tokens.Colors.secondaryText)
            }
        } header: {
            Text("About")
                .font(Tokens.Typography.title)
                .foregroundColor(Tokens.Colors.primaryText)
                .textCase(nil)
        }
    }

    // MARK: - Credits

    private var creditsSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Tokens.Colors.secondaryText)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Mubert")
                        .font(.body)
                        .foregroundColor(Tokens.Colors.primaryText)
                    Text("AI-generated background music")
                        .font(.caption)
                        .foregroundColor(Tokens.Colors.secondaryText)
                }
            }
        } header: {
            Text("Credits")
                .font(Tokens.Typography.title)
                .foregroundColor(Tokens.Colors.primaryText)
                .textCase(nil)
        }
    }

    // MARK: - Legal

    private var legalSection: some View {
        Section {
            Link(destination: URL(string: "https://studiomorph.com/privacy")!) {
                HStack {
                    Text("Privacy Policy")
                        .foregroundColor(Tokens.Colors.primaryText)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundColor(Tokens.Colors.secondaryText)
                }
            }

            Link(destination: URL(string: "https://studiomorph.com/terms")!) {
                HStack {
                    Text("Terms of Service")
                        .foregroundColor(Tokens.Colors.primaryText)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundColor(Tokens.Colors.secondaryText)
                }
            }
        } header: {
            Text("Legal")
                .font(Tokens.Typography.title)
                .foregroundColor(Tokens.Colors.primaryText)
                .textCase(nil)
        }
    }

    // MARK: - Sign Out

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                authManager.signOut()
            } label: {
                HStack {
                    Spacer()
                    Text("Sign Out")
                    Spacer()
                }
            }
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
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
