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
                        togetherCard
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
                    TapesLogo(height: 20, forceDark: true)
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
                tierHeader(suffix: "Plus", tier: .plus)

                HStack(alignment: .top, spacing: Tokens.Spacing.m) {
                    featureColumn([
                        .included("Unlimited TAPES"),
                        .included("Unlimited share TAPES"),
                        .included("No watermarks")
                    ])
                    featureColumn([
                        .included("12k music library"),
                        .included("AI mood music"),
                        .included("1 collab TAPE /month")
                    ])
                }
            }

            tierButton(
                label: "Upgrade to",
                suffix: "Plus",
                style: .primary
            ) {
                Task { await subManager.purchase(tier: .plus, cycle: billingCycle) }
            }
        }
        .padding(Tokens.Spacing.m)
        .background(Tokens.Colors.tertiaryBackground, in: RoundedRectangle(cornerRadius: cardRadius))
    }

    // MARK: - Together Card

    private var togetherCard: some View {
        VStack(spacing: Tokens.Spacing.m) {
            tierHeader(suffix: "Together", tier: .together)

            VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
                HStack(alignment: .top, spacing: Tokens.Spacing.m) {
                    featureColumn([.included("Everything in Plus")])
                    featureColumn([.included("AI prompt music")])
                }

                HStack(alignment: .top, spacing: Tokens.Spacing.xs) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Tokens.Colors.systemBlue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unlimited collaborative TAPES")
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

            tierButton(
                label: "Upgrade",
                suffix: "Together",
                style: .accent
            ) {
                Task { await subManager.purchase(tier: .together, cycle: billingCycle) }
            }
        }
        .padding(Tokens.Spacing.m)
        .background(Tokens.Colors.tertiaryBackground, in: RoundedRectangle(cornerRadius: cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cardRadius)
                .strokeBorder(Tokens.Colors.systemBlue, lineWidth: 4)
        )
    }

    // MARK: - Free Card

    private var freeCard: some View {
        VStack(spacing: Tokens.Spacing.m) {
            VStack(spacing: Tokens.Spacing.m) {
                HStack {
                    TapesLogo(height: 16, forceDark: true)
                    Spacer()
                    Text("Free")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Tokens.Colors.primaryText)
                }

                HStack(alignment: .top, spacing: Tokens.Spacing.m) {
                    VStack(alignment: .leading, spacing: 0) {
                        freeFeatureText("3 tapes/month")
                        freeFeatureText("1 shared tape")
                        freeFeatureText("Music library")
                    }

                    featureColumn([
                        .limitation("Watermark export"),
                        .excluded("No AI mood music"),
                        .excluded("0 Collaboration Tapes")
                    ])
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

    private func tierHeader(suffix: String, tier: SubscriptionManager.Tier) -> some View {
        HStack {
            TapesLogo(height: suffix == "Together" ? 20 : 16, suffix: suffix, forceDark: true)
            Spacer()
            priceLabel(for: tier)
        }
    }

    private func priceLabel(for tier: SubscriptionManager.Tier) -> some View {
        Group {
            if let product = subManager.product(for: tier, cycle: billingCycle) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(product.displayPrice)
                        .font(.system(size: 20, weight: .semibold))
                    Text(billingCycle == .monthly ? "/mo" : "/yr")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Tokens.Colors.primaryText)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(tier == .plus
                         ? (billingCycle == .monthly ? "£2,99" : "£24,99")
                         : (billingCycle == .monthly ? "£4,99" : "£41,99"))
                        .font(.system(size: 20, weight: .semibold))
                    Text(billingCycle == .monthly ? "/mo" : "/yr")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Tokens.Colors.primaryText)
            }
        }
    }

    private enum FeatureItem {
        case included(String)
        case limitation(String)
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

            case .limitation(let text):
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Tokens.Colors.systemRed)
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

    private func freeFeatureText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(Tokens.Colors.primaryText)
            .frame(height: 26)
    }

    private enum TierButtonStyle {
        case primary, accent
    }

    private func tierButton(
        label: String,
        suffix: String,
        style: TierButtonStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if subManager.isLoading {
                    ProgressView()
                        .tint(style == .primary ? Tokens.Colors.systemBlue : .white)
                } else {
                    HStack(spacing: 0) {
                        Text("\(label) ")
                            .font(.system(size: 16, weight: .medium))

                        Text("TAPES")
                            .font(.system(size: 16, weight: .heavy))

                        Text(suffix)
                            .font(.system(size: 16, weight: .light))
                    }
                    .foregroundStyle(style == .primary ? Tokens.Colors.systemBlue : Color.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Tokens.HitTarget.minimum)
            .background(
                style == .primary
                    ? AnyShapeStyle(Color.white)
                    : AnyShapeStyle(Tokens.Colors.systemBlue),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .disabled(subManager.isLoading)
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
