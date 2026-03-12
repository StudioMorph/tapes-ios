//
//  PaywallView.swift
//  Tapes
//
//  Created by AI Assistant on 26/01/2026.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @Environment(\.dismiss) private var dismiss

    private var subManager: SubscriptionManager { entitlementManager.subscriptionManager }
    private var trialManager: TrialManager { entitlementManager.trialManager }

    var body: some View {
        ZStack {
            backgroundGradient

            ScrollView {
                VStack(spacing: Tokens.Spacing.l) {
                    headerSection
                    featuresSection
                    pricingSection
                    actionButtons
                    footerLinks
                }
                .padding(.horizontal, Tokens.Spacing.m)
                .padding(.vertical, Tokens.Spacing.xl)
            }
        }
        .alert("Error", isPresented: alertBinding) {
            Button("OK") { subManager.purchaseError = nil }
        } message: {
            Text(subManager.purchaseError ?? "")
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

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Tokens.Spacing.s) {
            Image(systemName: "film.stack")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Tokens.Colors.systemRed, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.bottom, Tokens.Spacing.s)

            Text("Tapes Premium")
                .font(.largeTitle.bold())
                .foregroundColor(.white)

            Text("Unlimited creativity, no limits.")
                .font(.title3)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.top, Tokens.Spacing.xl)
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(spacing: Tokens.Spacing.m) {
            featureRow(icon: "film.stack.fill", title: "Unlimited Tapes", subtitle: "Create as many tapes as you want")
            featureRow(icon: "sparkles", title: "Premium Features", subtitle: "Access to all current and future features")
            featureRow(icon: "arrow.triangle.2.circlepath", title: "Priority Updates", subtitle: "Be the first to get new features")
        }
        .padding(Tokens.Spacing.l)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: Tokens.Spacing.m) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(Tokens.Colors.systemRed)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()
        }
    }

    // MARK: - Pricing

    private var pricingSection: some View {
        VStack(spacing: Tokens.Spacing.s) {
            if let product = subManager.monthlyProduct {
                pricingCard(product: product)
            } else {
                fallbackPricingCard
            }
        }
    }

    private var fallbackPricingCard: some View {
        VStack(spacing: Tokens.Spacing.s) {
            Text("Start for just £0.99")
                .font(.title2.bold())
                .foregroundColor(.white)

            Text("First 7 days · Then £2.99/month")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))

            Text("Cancel anytime")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(Tokens.Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .fill(
                    LinearGradient(
                        colors: [Tokens.Colors.systemRed.opacity(0.3), Tokens.Colors.systemRed.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.card)
                        .stroke(Tokens.Colors.systemRed.opacity(0.5), lineWidth: 1)
                )
        )
    }

    private func pricingCard(product: Product) -> some View {
        VStack(spacing: Tokens.Spacing.s) {
            if let intro = product.subscription?.introductoryOffer {
                Text("Start for just \(intro.displayPrice)")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                Text("First 7 days · Then \(product.displayPrice)/month")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            } else {
                Text("\(product.displayPrice)/month")
                    .font(.title2.bold())
                    .foregroundColor(.white)
            }

            Text("Cancel anytime")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(Tokens.Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
                .fill(
                    LinearGradient(
                        colors: [Tokens.Colors.systemRed.opacity(0.3), Tokens.Colors.systemRed.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.card)
                        .stroke(Tokens.Colors.systemRed.opacity(0.5), lineWidth: 1)
                )
        )
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: Tokens.Spacing.m) {
            Button {
                Task { await subManager.purchase() }
            } label: {
                Group {
                    if subManager.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Subscribe Now")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Tokens.Colors.systemRed, in: Capsule())
                .foregroundColor(.white)
            }
            .disabled(subManager.isLoading || subManager.monthlyProduct == nil)

            if trialManager.isTrialActive {
                Button {
                    dismiss()
                } label: {
                    Text("Continue Free Trial (\(trialManager.daysRemaining) days left)")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }

    // MARK: - Footer

    private var footerLinks: some View {
        VStack(spacing: Tokens.Spacing.s) {
            Button("Restore Purchases") {
                Task { await subManager.restore() }
            }
            .font(.caption)
            .foregroundColor(.white.opacity(0.5))

            HStack(spacing: Tokens.Spacing.m) {
                Link("Privacy Policy", destination: URL(string: "https://tapes.app/privacy")!)
                Text("·").foregroundColor(.white.opacity(0.3))
                Link("Terms of Use", destination: URL(string: "https://tapes.app/terms")!)
            }
            .font(.caption2)
            .foregroundColor(.white.opacity(0.4))
        }
        .padding(.top, Tokens.Spacing.s)
    }

    // MARK: - Alert Binding

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { subManager.purchaseError != nil },
            set: { if !$0 { subManager.purchaseError = nil } }
        )
    }
}

#Preview {
    PaywallView()
        .environmentObject(EntitlementManager())
}
