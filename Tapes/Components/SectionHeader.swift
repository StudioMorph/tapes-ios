import SwiftUI

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(Tokens.Typography.title)
            .foregroundColor(Tokens.Colors.onSurface)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
        SectionHeader(title: "Choose default transition")
        SectionHeader(title: "Transition Duration")
    }
    .padding()
    .background(Tokens.Colors.bg)
}
