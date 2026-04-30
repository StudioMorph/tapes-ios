import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedCycle: SubscriptionManager.BillingCycle = .annually

    private var subManager: SubscriptionManager { entitlementManager.subscriptionManager }

    private let cardCornerRadius: CGFloat = 24
    private let logoHeight: CGFloat = 28

    /// Apple's standard EULA — covers the Terms of Use half of our paywall
    /// legal link. The Privacy Policy half is being deferred; we'll point
    /// this at a combined in-app legal screen once the privacy text is
    /// drafted.
    private let legalURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Tokens.Spacing.l) {
                    headerLogo
                    headline
                    featureList
                    cycleCards
                    upgradeGroup
                    footer
                }
                .padding(.horizontal, Tokens.Spacing.l)
                .padding(.top, Tokens.Spacing.s)
                .padding(.bottom, Tokens.Spacing.xl)
            }
            .scrollContentBackground(.hidden)
            .background(Tokens.Colors.primaryBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Tokens.Colors.primaryText)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Error", isPresented: alertBinding) {
            Button("OK") { subManager.purchaseError = nil }
        } message: {
            Text(subManager.purchaseError ?? "")
        }
    }

    // MARK: - Header

    private var headerLogo: some View {
        Image(colorScheme == .dark ? "Tapes_Plus-Dark mode" : "Tapes_Plus-Light mode")
            .resizable()
            .scaledToFit()
            .frame(height: logoHeight)
            .accessibilityLabel("Tapes Plus")
    }

    private var headline: some View {
        (Text("Build ")
            + Text("Tapes").bold()
            + Text(" with friends and family"))
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(Tokens.Colors.primaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Feature list

    private struct Feature {
        enum Glyph { case check, sparkles }
        let glyph: Glyph
        let bold: String
        let trailing: String
    }

    private static let features: [Feature] = [
        Feature(glyph: .check,    bold: "NO ADS",       trailing: ""),
        Feature(glyph: .sparkles, bold: "AI",            trailing: "Text-to-Sound Track"),
        Feature(glyph: .check,    bold: "Unlimited",     trailing: "Sharing tapes"),
        Feature(glyph: .check,    bold: "Unlimited",     trailing: "Collab tapes"),
        Feature(glyph: .check,    bold: "12,000",        trailing: "Background sound tracks"),
        Feature(glyph: .check,    bold: "No Watermark",  trailing: "on export"),
        Feature(glyph: .check,    bold: "New features",  trailing: "every month")
    ]

    private var featureList: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            ForEach(Array(Self.features.enumerated()), id: \.offset) { _, feature in
                featureRow(feature)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func featureRow(_ feature: Feature) -> some View {
        HStack(spacing: Tokens.Spacing.s) {
            Image(systemName: feature.glyph == .sparkles ? "sparkles" : "checkmark.circle")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Tokens.Colors.primaryText)
                .frame(width: 20)

            featureText(bold: feature.bold, trailing: feature.trailing)
        }
    }

    private func featureText(bold: String, trailing: String) -> Text {
        if trailing.isEmpty {
            return Text(bold).bold()
        }
        return Text(bold).bold() + Text(" \(trailing)")
    }

    // MARK: - Cycle cards

    private var cycleCards: some View {
        VStack(spacing: Tokens.Spacing.s) {
            cycleCard(.annually)
            cycleCard(.monthly)
        }
    }

    @ViewBuilder
    private func cycleCard(_ cycle: SubscriptionManager.BillingCycle) -> some View {
        let isSelected = selectedCycle == cycle
        let product = subManager.product(for: cycle)
        let showsTrial = subManager.isEligibleForTrial(cycle: cycle)

        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCycle = cycle
            }
        } label: {
            HStack(alignment: .center, spacing: Tokens.Spacing.m) {
                selectionMark(isSelected: isSelected)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: Tokens.Spacing.s) {
                        Text(cycle == .annually ? "Annual" : "Monthly")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Tokens.Colors.primaryText)

                        Spacer(minLength: Tokens.Spacing.s)

                        if cycle == .annually {
                            // Optical-centre nudge: HStack `.center` aligns
                            // bounding boxes, but the price label box is
                            // taller (18pt cap-height + descenders + leading),
                            // so the pill ends up ~2pt below the visual
                            // mid-line of the price text. Lift it.
                            discountPill
                                .offset(y: -1)
                        }

                        priceLabel(for: product, cycle: cycle)
                    }

                    if showsTrial {
                        trialLine
                    }
                }
            }
            .padding(.vertical, Tokens.Spacing.m)
            .padding(.horizontal, Tokens.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.Colors.secondaryBackground, in: RoundedRectangle(cornerRadius: cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius)
                    .strokeBorder(
                        isSelected ? Tokens.Colors.systemBlue : Tokens.Colors.tertiaryBackground,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cycle == .annually ? "Annual subscription" : "Monthly subscription")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func selectionMark(isSelected: Bool) -> some View {
        ZStack {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Tokens.Colors.systemBlue)
            }
        }
        .frame(width: 24, height: 24)
    }

    private var discountPill: some View {
        Text("25% Off")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Tokens.Spacing.s)
            .padding(.vertical, 3)
            .background(Tokens.Colors.systemBlue, in: Capsule())
    }

    @ViewBuilder
    private func priceLabel(for product: Product?, cycle: SubscriptionManager.BillingCycle) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(product?.displayPrice ?? fallbackPrice(for: cycle))
                .font(.system(size: 18, weight: .semibold))
            Text(cycle == .monthly ? "/mo" : "/Yr")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Tokens.Colors.secondaryText)
        }
        .foregroundStyle(Tokens.Colors.primaryText)
    }

    private func fallbackPrice(for cycle: SubscriptionManager.BillingCycle) -> String {
        cycle == .monthly ? "£4.99" : "£44.99"
    }

    private var trialLine: some View {
        (Text("7 days Free Trial").bold()
            + Text("  ·  Cancel anytime"))
            .font(.system(size: 13))
            .foregroundStyle(Tokens.Colors.secondaryText)
    }

    // MARK: - Upgrade CTA + auto-renew caption

    /// Auto-renew caption belongs visually with the button — it's a
    /// disclosure about *that* action, not a footer line. Keeping them
    /// in the same VStack with an 8pt gap groups them correctly.
    private var upgradeGroup: some View {
        VStack(spacing: Tokens.Spacing.s) {
            upgradeButton
            Text("Will auto-renew unless cancelled")
                .font(.system(size: 12))
                .foregroundStyle(Tokens.Colors.tertiaryText)
        }
    }

    private var upgradeButton: some View {
        Button {
            Task { await subManager.purchase(cycle: selectedCycle) }
        } label: {
            ZStack {
                if subManager.isLoading {
                    ProgressView().tint(.white)
                } else {
                    HStack(spacing: 0) {
                        Text("Upgrade ")
                            .font(.system(size: 17, weight: .regular))
                        Text("Tapes").font(.system(size: 17, weight: .heavy))
                        Text("Plus").font(.system(size: 17, weight: .light))
                    }
                    .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Tokens.Colors.systemBlue, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(subManager.isLoading)
        .accessibilityLabel("Upgrade to Tapes Plus")
    }

    // MARK: - Footer (legal + restore)

    private var footer: some View {
        VStack(spacing: Tokens.Spacing.m) {
            Button {
                Task { await subManager.restore() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.trianglehead.2.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Restore Purchase")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Tokens.Colors.systemBlue)
            }
            .buttonStyle(.plain)
            .disabled(subManager.isLoading)

            Link(destination: legalURL) {
                HStack(spacing: 4) {
                    Text("Terms of Use (EULA) and Privacy Policy")
                        .font(.system(size: 12))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Tokens.Colors.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Tokens.Spacing.s)
    }

    // MARK: - Alert binding

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
