import SwiftUI
import AuthenticationServices

struct AccountSettingsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage("tapes_appearance_mode") private var appearanceMode: AppearanceMode = .dark

    private var isAppleSignedIn: Bool {
        authManager.userID != nil
    }

    var body: some View {
        NavigationView {
            Form {
                accountSection
                appearanceSection
                aboutSection
                creditsSection
                legalSection

                if isAppleSignedIn {
                    signOutSection
                }
            }
            .navigationTitle("Account & Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.blue)
                }
            }
        }
    }

    // MARK: - Account

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if isAppleSignedIn {
                if let name = authManager.userName {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(name)
                            .foregroundStyle(.secondary)
                    }
                }
                if let email = authManager.userEmail {
                    HStack {
                        Text("Email")
                        Spacer()
                        Text(email)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("Plan")
                    Spacer()
                    Text(entitlementManager.isPremium ? "Premium" : "Free")
                        .foregroundStyle(.secondary)
                }

                if !entitlementManager.isPremium {
                    Button("Manage Subscription") {
                        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sign in to sync your account and manage your subscription.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        authManager.handleAuthorization(result)
                    }
                    .frame(height: 48)
                    .clipShape(Capsule())
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Account")
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
        } footer: {
            Text("Choose how Tapes looks. System follows your device settings.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Build")
                Spacer()
                Text(appBuild)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Credits

    private var creditsSection: some View {
        Section {
            CreditRow(
                icon: "music.note",
                name: "Mubert",
                detail: "AI-generated background music"
            )
        } header: {
            Text("Credits")
        }
    }

    // MARK: - Legal

    private var legalSection: some View {
        Section {
            Link(destination: URL(string: "https://studiomorph.com/privacy")!) {
                HStack {
                    Text("Privacy Policy")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Link(destination: URL(string: "https://studiomorph.com/terms")!) {
                HStack {
                    Text("Terms of Service")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Legal")
        }
    }

    // MARK: - Sign Out

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                authManager.signOut()
                dismiss()
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

// MARK: - Credit Row

private struct CreditRow: View {
    let icon: String
    let name: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    AccountSettingsView()
        .environmentObject(AuthManager())
        .environmentObject(EntitlementManager())
}
