//
//  AuthManager.swift
//  Tapes
//
//  Created by AI Assistant on 26/01/2026.
//

import AuthenticationServices
import SwiftUI

@MainActor
final class AuthManager: ObservableObject {

    private static let userIDKey = "tapes_apple_user_id"
    private static let userNameKey = "tapes_apple_user_name"
    private static let userEmailKey = "tapes_apple_user_email"

    // MARK: - Published State

    @Published var isSignedIn: Bool = false
    @Published private(set) var userName: String?
    @Published private(set) var userEmail: String?
    @Published var authError: String?
    private(set) var didSignInThisSession: Bool = false

    // MARK: - Lifecycle

    init() {
        restoreSession()
    }

    // MARK: - Session

    var userID: String? {
        UserDefaults.standard.string(forKey: Self.userIDKey)
    }

    private func restoreSession() {
        guard let id = userID else {
            isSignedIn = false
            return
        }

        isSignedIn = true
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
            if let email = credential.email {
                userEmail = email
                UserDefaults.standard.set(email, forKey: Self.userEmailKey)
            }

            isSignedIn = true
            didSignInThisSession = true
            authError = nil

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

    // MARK: - Sign Out

    func signOut() {
        UserDefaults.standard.removeObject(forKey: Self.userIDKey)
        UserDefaults.standard.removeObject(forKey: Self.userNameKey)
        UserDefaults.standard.removeObject(forKey: Self.userEmailKey)
        isSignedIn = false
        userName = nil
        userEmail = nil
    }
}
