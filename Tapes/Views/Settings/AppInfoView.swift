import SwiftUI

struct AppInfoView: View {
    var body: some View {
        Form {
            versionSection.listRowBackground(Tokens.Colors.secondaryBackground)
            creditsSection.listRowBackground(Tokens.Colors.secondaryBackground)
            legalSection.listRowBackground(Tokens.Colors.secondaryBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
        .navigationTitle("App Info")
    }

    // MARK: - Version

    private var versionSection: some View {
        Section {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Build", value: appBuild)
        }
    }

    // MARK: - Credits

    private var creditsSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Tokens.Colors.secondaryText)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Mubert")
                        .font(.body)
                    Text("AI-generated background music")
                        .font(.caption)
                        .foregroundStyle(Tokens.Colors.secondaryText)
                }
            }
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
                        .foregroundStyle(Tokens.Colors.primaryText)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(Tokens.Colors.secondaryText)
                }
            }

            Link(destination: URL(string: "https://studiomorph.com/terms")!) {
                HStack {
                    Text("Terms of Service")
                        .foregroundStyle(Tokens.Colors.primaryText)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(Tokens.Colors.secondaryText)
                }
            }
        } header: {
            Text("Legal")
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

#Preview {
    NavigationStack {
        AppInfoView()
    }
}
