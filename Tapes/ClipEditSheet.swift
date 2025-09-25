import SwiftUI

struct ClipEditSheet: View {
    @Binding var isPresented: Bool
    let onAction: (ClipEditAction) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: Tokens.Space.xl) {
                trimSection
                fitInCanvasSection
                Spacer()
            }
            .padding(Tokens.Space.xl)
            .background(Tokens.Colors.bg)
            .navigationTitle("Edit Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundColor(Tokens.Colors.text)
                }
            }
        }
    }
    
    private var trimSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Button(action: {
                onAction(.trim)
                isPresented = false
            }) {
                HStack {
                    Text("Trim the clip's length")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Tokens.Colors.onAccent)
                    Spacer()
                }
                .padding(Tokens.Space.l)
                .background(Tokens.Colors.brandRed)
                .cornerRadius(Tokens.Radius.card)
            }
            
            Text("Trim the start or the end of the clip")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Tokens.Colors.muted)
        }
    }
    
    private var fitInCanvasSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            Text("Fit in canvas")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Tokens.Colors.text)
            
            VStack(spacing: Tokens.Space.s) {
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
                    .foregroundColor(Tokens.Colors.text)
                
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text("Fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Tokens.Colors.text)
                    
                    Text("Scale the clip to fill the canvas")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Tokens.Colors.muted)
                }
                
                Spacer()
                
                Image(systemName: "checkmark")
                    .font(.title2)
                    .foregroundColor(Tokens.Colors.brandRed)
            }
            .padding(Tokens.Space.l)
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
                    .foregroundColor(Tokens.Colors.text)
                
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text("Fit")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Tokens.Colors.text)
                    
                    Text("Fits the whole clip in the canvas")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Tokens.Colors.muted)
                }
                
                Spacer()
            }
            .padding(Tokens.Space.l)
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