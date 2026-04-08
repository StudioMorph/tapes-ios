import SwiftUI
import UIKit

private struct VariableBlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style
    var intensity: CGFloat

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView()
        context.coordinator.update(view: view, style: style, intensity: intensity)
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        context.coordinator.update(view: uiView, style: style, intensity: intensity)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var animator: UIViewPropertyAnimator?

        func update(view: UIVisualEffectView, style: UIBlurEffect.Style, intensity: CGFloat) {
            finishAnimator()
            view.effect = nil
            let newAnimator = UIViewPropertyAnimator(duration: 1, curve: .linear) {
                view.effect = UIBlurEffect(style: style)
            }
            newAnimator.startAnimation()
            newAnimator.pauseAnimation()
            newAnimator.fractionComplete = max(0, min(1, intensity))
            animator = newAnimator
        }

        private func finishAnimator() {
            guard let animator else { return }
            animator.stopAnimation(false)
            animator.finishAnimation(at: .current)
            self.animator = nil
        }

        deinit {
            finishAnimator()
        }
    }
}

struct ImportProgressOverlay: View {
    @ObservedObject var coordinator: MediaImportCoordinator

    var body: some View {
        if coordinator.isImporting {
            ZStack {
                VariableBlurView(style: .dark, intensity: 0.50)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ZStack {
                        CircularProgressRing(
                            progress: coordinator.progress,
                            lineWidth: 3.5,
                            size: 56,
                            ringColor: .blue
                        )

                        Image(systemName: "photo.stack")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.primary)
                    }

                    Text(coordinator.progressLabel)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.primary)

                    Button(role: .destructive) {
                        coordinator.cancelImport()
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .buttonBorderShape(.capsule)
                    .frame(maxWidth: 200)
                    .padding(.top, 8)
                }
            }
            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        }
    }
}
