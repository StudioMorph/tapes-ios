import SwiftUI
import os

@MainActor
final class AuthManager: ObservableObject {

    private static let userIDKey = "tapes_user_id"
    private static let userNameKey = "tapes_user_name"
    private static let userEmailKey = "tapes_user_email"
    private static let emailVerifiedKey = "tapes_email_verified"

    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "Auth")

    // MARK: - Published State

    @Published private(set) var userName: String?
    @Published private(set) var userEmail: String?
    @Published private(set) var userId: String?
    @Published private(set) var isEmailVerified = false
    @Published private(set) var isLoading = false
    @Published var authError: String?

    var apiClient: TapesAPIClient?

    // MARK: - Lifecycle

    init() {
        userId = UserDefaults.standard.string(forKey: Self.userIDKey)
        userName = UserDefaults.standard.string(forKey: Self.userNameKey)
        userEmail = UserDefaults.standard.string(forKey: Self.userEmailKey)
        isEmailVerified = UserDefaults.standard.bool(forKey: Self.emailVerifiedKey)
    }

    // MARK: - Session

    var isSignedIn: Bool { userId != nil }

    // MARK: - Register

    func register(email: String, password: String, firstName: String?, lastName: String?) async {
        guard let api = apiClient else {
            authError = "App not ready. Please try again."
            return
        }

        isLoading = true
        authError = nil
        defer { isLoading = false }

        do {
            let response = try await api.register(
                email: email,
                password: password,
                firstName: firstName,
                lastName: lastName
            )
            persistSession(from: response)
            log.info("Registration successful: \(response.user.userId)")
        } catch let apiError as APIError {
            authError = apiError.userMessage
        } catch {
            authError = "Something went wrong. Please try again."
            log.error("Register failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Login

    func login(email: String, password: String) async {
        guard let api = apiClient else {
            authError = "App not ready. Please try again."
            return
        }

        isLoading = true
        authError = nil
        defer { isLoading = false }

        do {
            let response = try await api.login(email: email, password: password)
            persistSession(from: response)
            log.info("Login successful: \(response.user.userId)")
        } catch let apiError as APIError {
            authError = apiError.userMessage
        } catch {
            authError = "Something went wrong. Please try again."
            log.error("Login failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Forgot Password

    func forgotPassword(email: String) async -> Bool {
        guard let api = apiClient else {
            authError = "App not ready. Please try again."
            return false
        }

        isLoading = true
        authError = nil
        defer { isLoading = false }

        do {
            _ = try await api.forgotPassword(email: email)
            return true
        } catch {
            authError = "Failed to send reset email. Please try again."
            return false
        }
    }

    // MARK: - Reset Password

    private var pendingResetResponse: TapesAPIClient.AuthResponse?

    func resetPassword(token: String, newPassword: String) async -> Bool {
        guard let api = apiClient else {
            authError = "App not ready. Please try again."
            return false
        }

        isLoading = true
        authError = nil
        defer { isLoading = false }

        do {
            let response = try await api.resetPassword(token: token, password: newPassword)
            pendingResetResponse = response
            log.info("Password reset successful")
            return true
        } catch let apiError as APIError {
            authError = apiError.userMessage
            return false
        } catch {
            authError = "Failed to reset password. Please try again."
            return false
        }
    }

    func commitResetSession() {
        guard let response = pendingResetResponse else { return }
        persistSession(from: response)
        pendingResetResponse = nil
    }

    // MARK: - Resend Verification

    func resendVerification() async -> Bool {
        guard let api = apiClient else { return false }

        do {
            _ = try await api.resendVerification()
            return true
        } catch {
            log.error("Resend verification failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Email Verified (called when deep link confirms)

    func markEmailVerified() {
        isEmailVerified = true
        UserDefaults.standard.set(true, forKey: Self.emailVerifiedKey)
    }

    // MARK: - Sign Out

    func signOut() {
        UserDefaults.standard.removeObject(forKey: Self.userIDKey)
        UserDefaults.standard.removeObject(forKey: Self.userNameKey)
        UserDefaults.standard.removeObject(forKey: Self.userEmailKey)
        UserDefaults.standard.removeObject(forKey: Self.emailVerifiedKey)
        userId = nil
        userName = nil
        userEmail = nil
        isEmailVerified = false

        if let api = apiClient {
            Task { await api.clearToken() }
        }
    }

    // MARK: - Private

    private func persistSession(from response: TapesAPIClient.AuthResponse) {
        userId = response.user.userId
        userName = response.user.name
        userEmail = response.user.email
        isEmailVerified = response.user.emailVerified ?? false

        UserDefaults.standard.set(response.user.userId, forKey: Self.userIDKey)
        if let name = response.user.name {
            UserDefaults.standard.set(name, forKey: Self.userNameKey)
        }
        if let email = response.user.email {
            UserDefaults.standard.set(email, forKey: Self.userEmailKey)
        }
        UserDefaults.standard.set(isEmailVerified, forKey: Self.emailVerifiedKey)
    }
}
