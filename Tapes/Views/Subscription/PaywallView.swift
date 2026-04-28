import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @Environment(\.dismiss) private var dismiss

    @State private var billingCycle: SubscriptionManager.BillingCycle = .monthly

    private var subManager: SubscriptionManager { entitlementManager.subscriptionManager }

    private let cardRadius: CGFloat = 28

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Tokens.Spacing.l) {
                    billingToggle
                        .padding(.top, Tokens.Spacing.m)

                    VStack(spacing: Tokens.Spacing.s) {
                        plusCard
                        freeCard
                    }
                }
                .padding(.horizontal, Tokens.Spacing.m)
                .padding(.bottom, Tokens.Spacing.m)
            }
            .scrollContentBackground(.hidden)
            .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TapesLogo(height: 20)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Tokens.Colors.primaryText)
                    }
                }
            }
        }
        .alert("Error", isPresented: alertBinding) {
            Button("OK") { subManager.purchaseError = nil }
        } message: {
            Text(subManager.purchaseError ?? "")
        }
    }

    // MARK: - Billing Toggle

    private var billingToggle: some View {
        Picker("Billing", selection: $billingCycle) {
            Text("Monthly").tag(SubscriptionManager.BillingCycle.monthly)
            Text("Annually -30%").tag(SubscriptionManager.BillingCycle.annually)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Plus Card

    private var plusCard: some View {
        VStack(spacing: Tokens.Spacing.m) {
            VStack(spacing: Tokens.Spacing.m) {
                HStack {
                    TapesLogo(height: 18, suffix: "Plus")
                    Spacer()
                    priceLabel
                }

                HStack(alignment: .top, spacing: Tokens.Spacing.m) {
                    featureColumn([
                        .included("NO ADS"),
                        .included("AI Background MUSIC")
                    ])
                    featureColumn([
                        .included("No Watermark export"),
                        .included("12K Background tracks")
                    ])
                }
            }

            heroFeature

            tierButton(action: {
                Task { await subManager.purchase(cycle: billingCycle) }
            })
        }
        .padding(Tokens.Spacing.m)
        .background(Tokens.Colors.tertiaryBackground, in: RoundedRectangle(cornerRadius: cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cardRadius)
                .strokeBorder(Tokens.Colors.systemBlue, lineWidth: 3)
        )
    }

    private var heroFeature: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.xs) {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Tokens.Colors.systemBlue)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Unlimited Share & Collab TAPES")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Tokens.Colors.primaryText)

                (Text("Get your family, friends, to build ")
                    + Text("TAPES").bold()
                    + Text(" together with you"))
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.Colors.secondaryText)
            }
        }
    }

    private var priceLabel: some View {
        Group {
            if let product = subManager.product(for: billingCycle) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(product.displayPrice)
                        .font(.system(size: 20, weight: .semibold))
                    Text(billingCycle == .monthly ? "/mo" : "/yr")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Tokens.Colors.primaryText)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(billingCycle == .monthly ? "£3.99" : "£33.49")
                        .font(.system(size: 20, weight: .semibold))
                    Text(billingCycle == .monthly ? "/mo" : "/yr")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Tokens.Colors.primaryText)
            }
        }
    }

    private func tierButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if subManager.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    HStack(spacing: 0) {
                        Text("Upgrade ")
                            .font(.system(size: 16, weight: .medium))

                        Text("TAPES")
                            .font(.system(size: 16, weight: .heavy))

                        Text("Plus")
                            .font(.system(size: 16, weight: .light))
                    }
                    .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Tokens.HitTarget.minimum)
            .background(Tokens.Colors.systemBlue, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(subManager.isLoading)
    }

    // MARK: - Free Card

    private var freeCard: some View {
        VStack(spacing: Tokens.Spacing.m) {
            VStack(spacing: Tokens.Spacing.m) {
                HStack {
                    TapesLogo(height: 18, suffix: "Free")
                    Spacer()
                    Text("Free")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Tokens.Colors.primaryText)
                }

                HStack(alignment: .top, spacing: Tokens.Spacing.m) {
                    featureColumn([
                        .included("Unlimited local tapes"),
                        .included("5 Share/ collab Tapes"),
                        .included("Background Music")
                    ])

                    VStack(alignment: .leading, spacing: 0) {
                        freeDetailText("ADS before Playing")
                        freeDetailText("Watermark on Export")
                        featureRow(.excluded("No AI Music"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Text("This is you")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Tokens.Colors.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: Tokens.HitTarget.minimum)
                .background(Tokens.Colors.primaryText.opacity(0.1), in: Capsule())
        }
        .padding(Tokens.Spacing.m)
        .background(Tokens.Colors.tertiaryBackground, in: RoundedRectangle(cornerRadius: cardRadius))
    }

    // MARK: - Shared Components

    private enum FeatureItem {
        case included(String)
        case excluded(String)
    }

    private func featureColumn(_ items: [FeatureItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                featureRow(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func featureRow(_ item: FeatureItem) -> some View {
        HStack(spacing: 4) {
            switch item {
            case .included(let text):
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Tokens.Colors.systemBlue)
                Text(text)
                    .foregroundStyle(Tokens.Colors.primaryText)

            case .excluded(let text):
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Tokens.Colors.systemRed)
                Text(text)
                    .foregroundStyle(Tokens.Colors.primaryText)
            }
        }
        .font(.system(size: 14))
        .frame(height: 26)
    }

    private func freeDetailText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(Tokens.Colors.primaryText)
            .frame(height: 26)
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
