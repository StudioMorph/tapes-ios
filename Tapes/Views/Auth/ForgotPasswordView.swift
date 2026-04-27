import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var sent = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if sent {
                    sentState
                } else {
                    inputState
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
            .navigationTitle("Reset Password")
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
            Text("Enter the email address you used to create your account and we'll send you a link to reset your password.")
                .font(.system(size: 15))
                .foregroundStyle(Tokens.Colors.secondaryText)
                .multilineTextAlignment(.center)

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Tokens.Colors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if let error = authManager.authError {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let success = await authManager.forgotPassword(email: trimmed)
                    if success { sent = true }
                }
            } label: {
                ZStack {
                    Text("Send Reset Link")
                        .font(.system(size: 17, weight: .semibold))
                        .opacity(authManager.isLoading ? 0 : 1)
                    ProgressView()
                        .tint(.white)
                        .opacity(authManager.isLoading ? 1 : 0)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authManager.isLoading)
        }
    }

    // MARK: - Sent State

    private var sentState: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Check your inbox")
                .font(.system(size: 20, weight: .semibold))

            Text("If an account exists for **\(email.trimmingCharacters(in: .whitespacesAndNewlines))**, you'll receive a link to reset your password.")
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

            Button("Resend") {
                sent = false
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.blue)
        }
    }
}
