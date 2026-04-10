import SwiftUI

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(Tokens.Typography.title)
            .foregroundColor(Tokens.Colors.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Tokens.Spacing.m)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
        SectionHeader(title: "Choose default transition")
        SectionHeader(title: "Transition Duration")
    }
    .padding()
    .background(Tokens.Colors.primaryBackground)
}
