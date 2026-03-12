//
//  SignInView.swift
//  Tapes
//
//  Created by AI Assistant on 26/01/2026.
//

import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: Tokens.Spacing.xl) {
                Spacer()

                brandingSection
                taglineSection

                Spacer()

                signInSection
                skipSection

                Spacer()
                    .frame(height: Tokens.Spacing.xl)
            }
            .padding(.horizontal, Tokens.Spacing.l)
        }
        .alert("Sign In Error", isPresented: alertBinding) {
            Button("OK") { authManager.authError = nil }
        } message: {
            Text(authManager.authError ?? "")
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.05, blue: 0.15),
                Color(red: 0.1, green: 0.02, blue: 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Branding

    private var brandingSection: some View {
        VStack(spacing: Tokens.Spacing.m) {
            Image(systemName: "film.stack.fill")
                .font(.system(size: 72))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Tokens.Colors.systemRed, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("TAPES")
                .font(.system(size: 42, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .tracking(6)
        }
    }

    private var taglineSection: some View {
        VStack(spacing: Tokens.Spacing.s) {
            Text("Create. Compose. Share.")
                .font(.title3.weight(.medium))
                .foregroundColor(.white.opacity(0.8))

            Text("Your stories, beautifully told.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Sign In

    private var signInSection: some View {
        VStack(spacing: Tokens.Spacing.m) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                authManager.handleAuthorization(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 54)
            .clipShape(Capsule())
        }
    }

    // MARK: - Skip

    private var skipSection: some View {
        Button {
            authManager.isSignedIn = true
        } label: {
            Text("Skip for now")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Alert Binding

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { authManager.authError != nil },
            set: { if !$0 { authManager.authError = nil } }
        )
    }
}

#Preview("Sign In") {
    SignInView()
        .environmentObject(AuthManager())
}
