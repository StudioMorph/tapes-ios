import SwiftUI

struct ClipEditSheet: View {
    @Binding var isPresented: Bool
    let onAction: (ClipEditAction) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: Tokens.Spacing.l) {
                trimSection
                fitInCanvasSection
                Spacer()
            }
            .padding(Tokens.Spacing.l)
            .background(Tokens.Colors.bg)
            .navigationTitle("Edit Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundColor(Tokens.Colors.onSurface)
                }
            }
        }
    }
    
    private var trimSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            Button(action: {
                onAction(.trim)
                isPresented = false
            }) {
                HStack {
                    Text("Trim the clip's length")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Tokens.Colors.onSurface)
                    Spacer()
                }
                .padding(Tokens.Spacing.l)
                .background(Tokens.Colors.red)
                .cornerRadius(Tokens.Radius.card)
            }
            
            Text("Trim the start or the end of the clip")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Tokens.Colors.onSurface.opacity(0.6))
        }
    }
    
    private var fitInCanvasSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
            Text("Fit in canvas")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Tokens.Colors.onSurface)
            
            VStack(spacing: Tokens.Spacing.s) {
                fillOption
                fitOption
            }
        }
    }
    
    private var fillOption: some View {
        Button(action: {
            onAction(.setFitFill(.fill))
            isPresented = false
        }) {
            HStack {
                Image(systemName: "rectangle.fill")
                    .font(.title2)
                    .foregroundColor(Tokens.Colors.onSurface)
                
                VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
                    Text("Fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Tokens.Colors.onSurface)
                    
                    Text("Scale the clip to fill the canvas")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Tokens.Colors.onSurface.opacity(0.6))
                }
                
                Spacer()
                
                Image(systemName: "checkmark")
                    .font(.title2)
                    .foregroundColor(Tokens.Colors.red)
            }
            .padding(Tokens.Spacing.l)
            .background(Tokens.Colors.elevated)
            .cornerRadius(Tokens.Radius.card)
        }
    }
    
    private var fitOption: some View {
        Button(action: {
            onAction(.setFitFill(.fit))
            isPresented = false
        }) {
            HStack {
                Image(systemName: "rectangle")
                    .font(.title2)
                    .foregroundColor(Tokens.Colors.onSurface)
                
                VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
                    Text("Fit")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Tokens.Colors.onSurface)
                    
                    Text("Fits the whole clip in the canvas")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Tokens.Colors.onSurface.opacity(0.6))
                }
                
                Spacer()
            }
            .padding(Tokens.Spacing.l)
            .background(Tokens.Colors.elevated)
            .cornerRadius(Tokens.Radius.card)
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