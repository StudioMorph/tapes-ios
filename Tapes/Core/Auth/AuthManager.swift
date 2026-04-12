//
//  AuthManager.swift
//  Tapes
//
//  Created by AI Assistant on 26/01/2026.
//

import AuthenticationServices
import SwiftUI
import os

@MainActor
final class AuthManager: ObservableObject {

    private static let userIDKey = "tapes_apple_user_id"
    private static let userNameKey = "tapes_apple_user_name"
    private static let userEmailKey = "tapes_apple_user_email"
    private static let serverUserIDKey = "tapes_server_user_id"

    private let log = Logger(subsystem: "com.studiomorph.tapes", category: "Auth")

    // MARK: - Published State

    @Published private(set) var userName: String?
    @Published private(set) var userEmail: String?
    @Published private(set) var serverUserId: String?
    @Published private(set) var isAuthenticatingWithServer = false
    @Published var authError: String?

    var apiClient: TapesAPIClient?

    // MARK: - Lifecycle

    init() {
        serverUserId = UserDefaults.standard.string(forKey: Self.serverUserIDKey)
        restoreSession()
    }

    // MARK: - Session

    var userID: String? {
        UserDefaults.standard.string(forKey: Self.userIDKey)
    }

    var isSignedIn: Bool {
        userID != nil
    }

    var hasServerSession: Bool {
        apiClient?.isAuthenticated ?? false
    }

    private func restoreSession() {
        guard let id = userID else { return }

        userName = UserDefaults.standard.string(forKey: Self.userNameKey)
        userEmail = UserDefaults.standard.string(forKey: Self.userEmailKey)

        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: id) { [weak self] state, _ in
            Task { @MainActor in
                switch state {
                case .revoked, .notFound:
                    self?.signOut()
                default:
                    break
                }
            }
        }
    }

    // MARK: - Handle Sign in with Apple Result

    func handleAuthorization(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                authError = "Unexpected credential type."
                return
            }

            let uid = credential.user
            UserDefaults.standard.set(uid, forKey: Self.userIDKey)

            if let fullName = credential.fullName {
                let name = PersonNameComponentsFormatter.localizedString(from: fullName, style: .default)
                if !name.isEmpty {
                    userName = name
                    UserDefaults.standard.set(name, forKey: Self.userNameKey)
                }
            }
            if userName == nil {
                userName = UserDefaults.standard.string(forKey: Self.userNameKey)
            }

            if let email = credential.email {
                userEmail = email
                UserDefaults.standard.set(email, forKey: Self.userEmailKey)
            }
            if userEmail == nil {
                userEmail = UserDefaults.standard.string(forKey: Self.userEmailKey)
            }

            authError = nil

            // Exchange Apple identity token for server access token
            if let identityToken = credential.identityToken, let api = apiClient {
                Task {
                    await exchangeTokenWithServer(
                        identityToken: identityToken,
                        fullName: userName,
                        email: userEmail,
                        api: api
                    )
                }
            }

        case .failure(let error):
            guard let asError = error as? ASAuthorizationError else {
                authError = error.localizedDescription
                return
            }
            switch asError.code {
            case .canceled, .unknown:
                break
            default:
                authError = error.localizedDescription
            }
        }
    }

    // MARK: - Server Token Exchange

    private func exchangeTokenWithServer(identityToken: Data, fullName: String?,
                                          email: String?, api: TapesAPIClient) async {
        isAuthenticatingWithServer = true
        defer { isAuthenticatingWithServer = false }

        do {
            let response = try await api.authenticateWithApple(
                identityToken: identityToken,
                fullName: fullName,
                email: email
            )
            serverUserId = response.user.userId
            UserDefaults.standard.set(response.user.userId, forKey: Self.serverUserIDKey)
            log.info("Server auth successful, user: \(response.user.userId)")
        } catch {
            log.error("Server auth failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Sign Out

    func signOut() {
        UserDefaults.standard.removeObject(forKey: Self.userIDKey)
        UserDefaults.standard.removeObject(forKey: Self.serverUserIDKey)
        userName = nil
        userEmail = nil
        serverUserId = nil

        if let api = apiClient {
            Task { await api.clearToken() }
        }
    }
}
