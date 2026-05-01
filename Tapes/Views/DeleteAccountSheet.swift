import SwiftUI

struct DeleteAccountSheet: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var isRequesting = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Tokens.Spacing.l) {
                Spacer()

                TapesLogo(height: 36)

                Text("Are you sure you want to delete your account and all associated data?")
                    .font(Tokens.Typography.title)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Tokens.Colors.primaryText)
                    .padding(.top, Tokens.Spacing.m)

                VStack(spacing: Tokens.Spacing.m) {
                    Text("You will be signed out immediately. Your account and data will be permanently deleted after a 7-day cooling-off period.")
                        .font(Tokens.Typography.body)
                        .foregroundStyle(Tokens.Colors.primaryText)
                        .multilineTextAlignment(.center)

                    Text("If you sign back in during those 7 days, the deletion will be cancelled automatically.")
                        .font(.system(.body, design: .default, weight: .medium))
                        .foregroundStyle(Tokens.Colors.primaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Tokens.Spacing.l)
                .padding(.bottom, Tokens.Spacing.l)

                VStack(spacing: Tokens.Spacing.xs) {
                    Image(systemName: "apple.logo")
                        .font(.body)
                        .foregroundStyle(Tokens.Colors.secondaryText)
                    Text("To cancel a subscription, go to Settings > Apple ID > Subscriptions on your device.")
                        .font(.subheadline)
                        .foregroundStyle(Tokens.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Tokens.Spacing.xl)

                Spacer()

                VStack(spacing: Tokens.Spacing.s) {
                    Button {
                        dismiss()
                    } label: {
                        Text("No, I want to stay")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: Tokens.HitTarget.minimum)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Tokens.Colors.systemBlue)

                    Button(role: .destructive) {
                        Task { await requestDeletion() }
                    } label: {
                        if isRequesting {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: Tokens.HitTarget.minimum)
                        } else {
                            Text("Yes, delete my account and data")
                                .frame(maxWidth: .infinity, minHeight: Tokens.HitTarget.minimum)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRequesting)
                }
                .padding(.horizontal, Tokens.Spacing.m)
                .padding(.bottom, Tokens.Spacing.l)
            }
            .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Something went wrong", isPresented: $showError) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again later.")
            }
        }
    }

    private func requestDeletion() async {
        guard let api = authManager.apiClient else { return }
        isRequesting = true
        defer { isRequesting = false }

        do {
            _ = try await api.requestAccountDeletion()
            authManager.signOut()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    DeleteAccountSheet()
        .environmentObject(AuthManager())
}
