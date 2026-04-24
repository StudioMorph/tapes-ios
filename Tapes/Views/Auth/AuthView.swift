import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.colorScheme) private var colorScheme

    enum AuthMode: String, CaseIterable {
        case login = "Log In"
        case register = "Create Account"
    }

    @State private var mode: AuthMode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var showForgotPassword = false
    @Binding var resetPasswordToken: String?

    private var isFormValid: Bool {
        let emailValid = !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let passwordValid = password.count >= 8

        switch mode {
        case .login:
            return emailValid && !password.isEmpty
        case .register:
            return emailValid && passwordValid && password == confirmPassword
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                logo
                    .padding(.top, 60)
                    .padding(.bottom, 36)

                picker
                    .padding(.bottom, 32)

                fields
                    .padding(.bottom, 8)

                if mode == .login {
                    forgotPasswordLink
                        .padding(.bottom, 24)
                } else {
                    Spacer().frame(height: 24)
                }

                if let error = authManager.authError {
                    errorBanner(error)
                        .padding(.bottom, 16)
                }

                submitButton
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView()
        }
        .sheet(item: $resetPasswordToken) { token in
            ResetPasswordView(token: token)
        }
        .onChange(of: resetPasswordToken) { _, newToken in
            if newToken != nil {
                showForgotPassword = false
            }
        }
        .onChange(of: mode) { _, _ in
            authManager.authError = nil
        }
    }

    // MARK: - Logo

    private var logo: some View {
        Image(colorScheme == .dark ? "Tapes_logo-Dark mode" : "Tapes_logo-Light mode")
            .resizable()
            .scaledToFit()
            .frame(height: 36)
    }

    // MARK: - Segmented Picker

    private var picker: some View {
        Picker("", selection: $mode) {
            ForEach(AuthMode.allCases, id: \.self) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
    }

    // MARK: - Fields

    private var fields: some View {
        VStack(spacing: 16) {
            if mode == .register {
                HStack(spacing: 12) {
                    LabeledField(label: "First Name") {
                        TextField("", text: $firstName)
                            .textContentType(.givenName)
                            .autocorrectionDisabled()
                    }

                    LabeledField(label: "Last Name") {
                        TextField("", text: $lastName)
                            .textContentType(.familyName)
                            .autocorrectionDisabled()
                    }
                }
            }

            LabeledField(label: "Email") {
                TextField("", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            SecureInputField(
                label: "Password",
                text: $password,
                textContentType: mode == .register ? .newPassword : .password
            )

            if mode == .register {
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
        }
        .animation(.easeInOut(duration: 0.25), value: mode)
    }

    // MARK: - Forgot Password

    private var forgotPasswordLink: some View {
        HStack {
            Spacer()
            Button("Forgot Password?") {
                showForgotPassword = true
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.blue)
        }
    }

    // MARK: - Error

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            Group {
                if authManager.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(mode == .login ? "Log In" : "Create Account")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isFormValid || authManager.isLoading)
    }

    // MARK: - Actions

    private func submit() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch mode {
        case .login:
            await authManager.login(email: trimmedEmail, password: password)
        case .register:
            let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            await authManager.register(
                email: trimmedEmail,
                password: password,
                firstName: first.isEmpty ? nil : first,
                lastName: last.isEmpty ? nil : last
            )
        }
    }
}

// MARK: - Labeled Field

struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)

            content
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Tokens.Colors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

// MARK: - Secure Input Field (with eye toggle)

struct SecureInputField: View {
    let label: String
    @Binding var text: String
    var textContentType: UITextContentType = .password

    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Tokens.Colors.secondaryText)

            HStack(spacing: 8) {
                Group {
                    if isRevealed {
                        TextField("", text: $text)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("", text: $text)
                    }
                }
                .textContentType(textContentType)

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 15))
                        .foregroundStyle(Tokens.Colors.tertiaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Tokens.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
