import SwiftUI

struct ResetPasswordView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    let token: String

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var success = false

    private var isFormValid: Bool {
        password.count >= 8 && password == confirmPassword
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if success {
                    successState
                } else {
                    inputState
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
            .navigationTitle("New Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("New Password")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Tokens.Colors.secondaryText)

                    SecureField("", text: $password)
                        .textContentType(.newPassword)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Tokens.Colors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Confirm Password")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Tokens.Colors.secondaryText)

                    SecureField("", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Tokens.Colors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            if password.count > 0 && password.count < 8 {
                Text("Password must be at least 8 characters")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
            }

            if !confirmPassword.isEmpty && password != confirmPassword {
                Text("Passwords don't match")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }

            if let error = authManager.authError {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    let ok = await authManager.resetPassword(token: token, newPassword: password)
                    if ok { success = true }
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
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isFormValid || authManager.isLoading)
        }
    }

    // MARK: - Success State

    private var successState: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Password Reset")
                .font(.system(size: 20, weight: .semibold))

            Text("Your password has been updated and you're signed in.")
                .font(.system(size: 15))
                .foregroundStyle(Tokens.Colors.secondaryText)
                .multilineTextAlignment(.center)

            Button("Continue") { dismiss() }
                .font(.system(size: 17, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}
