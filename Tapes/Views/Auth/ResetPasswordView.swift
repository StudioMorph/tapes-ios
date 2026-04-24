import SwiftUI

struct ResetPasswordView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    let token: String

    enum ViewState {
        case loading
        case expired(String)
        case input
        case success
    }

    @State private var viewState: ViewState = .loading
    @State private var password = ""
    @State private var confirmPassword = ""

    private var isFormValid: Bool {
        password.count >= 8 && password == confirmPassword
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch viewState {
                case .loading:
                    Spacer()
                    ProgressView()
                    Spacer()
                case .expired(let message):
                    expiredState(message: message)
                case .input:
                    inputState
                case .success:
                    successState
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await validateToken() }
        }
    }

    private var navTitle: String {
        switch viewState {
        case .expired: return "Link Expired"
        case .success: return "Password Reset"
        default: return "New Password"
        }
    }

    // MARK: - Validate Token

    private func validateToken() async {
        guard let api = authManager.apiClient else {
            viewState = .expired("App not ready. Please try again.")
            return
        }

        do {
            try await api.validateResetToken(token)
            viewState = .input
        } catch {
            let message = (error as? APIError)?.userMessage
                ?? "This link has expired or has already been used."
            viewState = .expired(message)
        }
    }

    // MARK: - Expired State

    private func expiredState(message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.red)

            Text("Link Expired")
                .font(.system(size: 20, weight: .semibold))

            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Tokens.Colors.secondaryText)
                .multilineTextAlignment(.center)

            Button {
                dismiss()
            } label: {
                Text("Got it")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
    }

    // MARK: - Input State

    private var inputState: some View {
        VStack(spacing: 20) {
            Text("Enter your new password below.")
                .font(.system(size: 15))
                .foregroundStyle(Tokens.Colors.secondaryText)
                .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                SecureInputField(
                    label: "New Password",
                    text: $password,
                    textContentType: .newPassword
                )

                if !password.isEmpty && password.count < 8 {
                    Text("Password must be at least 8 characters")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                SecureInputField(
                    label: "Confirm Password",
                    text: $confirmPassword,
                    textContentType: .newPassword
                )

                if !confirmPassword.isEmpty && password != confirmPassword {
                    Text("Passwords don't match")
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let error = authManager.authError {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    let ok = await authManager.resetPassword(token: token, newPassword: password)
                    if ok { viewState = .success }
                }
            } label: {
                Group {
                    if authManager.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Reset Password")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isFormValid || authManager.isLoading)
        }
    }

    // MARK: - Success State

    private var successState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Password Reset")
                .font(.system(size: 20, weight: .semibold))

            Text("Your password has been updated and you're signed in.")
                .font(.system(size: 15))
                .foregroundStyle(Tokens.Colors.secondaryText)
                .multilineTextAlignment(.center)

            Button {
                authManager.commitResetSession()
                dismiss()
            } label: {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
    }
}
