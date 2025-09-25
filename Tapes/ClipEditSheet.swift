import SwiftUI

struct ClipEditSheet: View {
    @Binding var isPresented: Bool
    let onAction: (ClipEditAction) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: Tokens.Space.s24) {
                // Trim option
                Button(action: {
                    onAction(.trim)
                    isPresented = false
                }) {
                    HStack {
                        Text("Trim the clip's length")
                            .font(Tokens.Typography.title)
                            .foregroundColor(Tokens.Colors.textOnAccent)
                        Spacer()
                    }
                    .padding(Tokens.Space.s16)
                    .background(Tokens.Colors.brandRed)
                    .cornerRadius(Tokens.Radius.card)
                }
                
                VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                    Text("Trim the start or the end of the clip")
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Tokens.Colors.textMuted)
                }
                
                // Fit in canvas section
                VStack(alignment: .leading, spacing: Tokens.Space.s16) {
                    Text("Fit in canvas")
                        .font(Tokens.Typography.title)
                        .foregroundColor(Tokens.Colors.textPrimary)
                    
                    // Fill option
                    Button(action: {
                        onAction(.setFitFill(.fill))
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: "rectangle.fill")
                                .font(.title2)
                                .foregroundColor(Tokens.Colors.textPrimary)
                            
                            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                                Text("Fill")
                                    .font(Tokens.Typography.title)
                                    .foregroundColor(Tokens.Colors.textPrimary)
                                
                                Text("Scale the clip to fill the canvas")
                                    .font(Tokens.Typography.caption)
                                    .foregroundColor(Tokens.Colors.textMuted)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "checkmark")
                                .font(.title2)
                                .foregroundColor(Tokens.Colors.brandRed)
                        }
                        .padding(Tokens.Space.s16)
                        .background(Tokens.Colors.surfaceElevated)
                        .cornerRadius(Tokens.Radius.card)
                    }
                    
                    // Fit option
                    Button(action: {
                        onAction(.setFitFill(.fit))
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: "rectangle")
                                .font(.title2)
                                .foregroundColor(Tokens.Colors.textPrimary)
                            
                            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                                Text("Fit")
                                    .font(Tokens.Typography.title)
                                    .foregroundColor(Tokens.Colors.textPrimary)
                                
                                Text("Fits the whole clip in the canvas")
                                    .font(Tokens.Typography.caption)
                                    .foregroundColor(Tokens.Colors.textMuted)
                            }
                            
                            Spacer()
                        }
                        .padding(Tokens.Space.s16)
                        .background(Tokens.Colors.surfaceElevated)
                        .cornerRadius(Tokens.Radius.card)
                    }
                }
                
                Spacer()
            }
            .padding(Tokens.Space.s20)
            .background(Tokens.Colors.bg)
            .navigationTitle("Edit Clip")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    isPresented = false
                }
            )
        }
    }
}

enum ClipEditAction {
    case trim
    case rotate
    case setFitFill(FitFillMode)
    case share
    case remove
}

enum FitFillMode {
    case fit
    case fill
}

#Preview("Dark Mode") {
    ClipEditSheet(
        isPresented: .constant(true),
        onAction: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("Light Mode") {
    ClipEditSheet(
        isPresented: .constant(true),
        onAction: { _ in }
    )
    .preferredColorScheme(.light)
}