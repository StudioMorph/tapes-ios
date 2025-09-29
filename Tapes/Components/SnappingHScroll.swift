import SwiftUI

/// A horizontal scroll container that snaps so the *gap between items* aligns with the visual center.
struct SnappingHScroll<Content: View>: UIViewRepresentable {
    let itemWidth: CGFloat
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    let containerWidth: CGFloat
    let onSnapped: ((Int, Int) -> Void)?
    let savedOffset: CGFloat?
    let onOffsetChanged: ((CGFloat) -> Void)?
    let targetSnapIndex: Int?
    let content: () -> Content

    init(itemWidth: CGFloat,
         leadingInset: CGFloat = 16,
         trailingInset: CGFloat = 16,
         containerWidth: CGFloat,
         onSnapped: ((Int, Int) -> Void)? = nil,
         savedOffset: CGFloat? = nil,
         onOffsetChanged: ((CGFloat) -> Void)? = nil,
         targetSnapIndex: Int? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.itemWidth = itemWidth
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
        self.containerWidth = containerWidth
        self.onSnapped = onSnapped
        self.savedOffset = savedOffset
        self.onOffsetChanged = onOffsetChanged
        self.targetSnapIndex = targetSnapIndex
        self.content = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.delegate = context.coordinator
        scrollView.decelerationRate = .fast

        // Build UIHostingController to host SwiftUI content
        let hosting = UIHostingController(rootView:
            HStack(spacing: 0) {
                content()
            }
        )
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        scrollView.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),

            hosting.view.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        context.coordinator.hostingController = hosting
        context.coordinator.scrollView = scrollView
        
        // Restore saved scroll position if available
        if let savedOffset = savedOffset {
            print("🎯 Restoring scroll position: \(savedOffset)")
            DispatchQueue.main.async {
                scrollView.setContentOffset(CGPoint(x: savedOffset, y: 0), animated: false)
            }
        }
        
        // Scroll to target snap index if provided
        if let targetIndex = targetSnapIndex {
            print("🎯 Scrolling to target snap index: \(targetIndex)")
            DispatchQueue.main.async {
                let targetOffset = leadingInset + CGFloat(targetIndex) * itemWidth
                scrollView.setContentOffset(CGPoint(x: targetOffset, y: 0), animated: true)
            }
        }
        
        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        // No-op; SwiftUI content updates through hosting controller automatically.
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: SnappingHScroll
        weak var hostingController: UIHostingController<HStack<Content>>?
        weak var scrollView: UIScrollView?

        // We need to know total content width (calculated on the fly)
        init(parent: SnappingHScroll) {
            self.parent = parent
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // Track scroll position changes
            parent.onOffsetChanged?(scrollView.contentOffset.x)
        }

        func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                       withVelocity velocity: CGPoint,
                                       targetContentOffset: UnsafeMutablePointer<CGPoint>) {

            guard parent.itemWidth > 0 else { 
                print("⚠️ SnappingHScroll: itemWidth is 0 or negative")
                return 
            }

            // Where the system plans to stop
            let proposedX = targetContentOffset.pointee.x

            // The horizontal center of the visible container (card center under the FAB)
            let centerX = parent.containerWidth / 2.0

            // Compute nearest boundary (gap) so that boundary aligns with centerX
            // Boundaries are at: leadingInset + n*itemWidth for n = 1...N-1
            // If you want snapping also to start/end placeholders, include n=0 and n=N (below we do).
            // First, estimate n from proposed offset:
            // boundaryX - offset = centerX  =>  offset = boundaryX - centerX
            // boundaryX ≈ proposedX + centerX  (rough estimate)
            let estimatedBoundaryX = proposedX + centerX

            // Convert to nearest boundary index
            let rawN = (estimatedBoundaryX - parent.leadingInset) / parent.itemWidth
            print("🔍 SnappingHScroll: rawN = \(rawN), itemWidth = \(parent.itemWidth), leadingInset = \(parent.leadingInset)")
            
            var n = round(rawN)
            if n < 0 { n = 0 }
            // We can't know N precisely here; clamp later using content size.

            // Compute snapped boundaryX from n
            let snappedBoundaryX = parent.leadingInset + n * parent.itemWidth

            // Compute target offset so center aligns on that boundary
            var snappedOffsetX = snappedBoundaryX - centerX

            // Clamp to valid range
            let maxOffsetX = max(0, (scrollView.contentSize.width - parent.containerWidth))
            snappedOffsetX = min(max(snappedOffsetX, 0), maxOffsetX)

            print("🔍 SnappingHScroll: n = \(n), snappedOffsetX = \(snappedOffsetX), maxOffsetX = \(maxOffsetX)")

            // Call snapping callback if provided
            if let onSnapped = parent.onSnapped {
                let leftIndex = Int(n)
                let totalCount = Int((scrollView.contentSize.width - parent.leadingInset - parent.trailingInset) / parent.itemWidth)
                onSnapped(leftIndex, totalCount)
            }

            // Assign final target
            targetContentOffset.pointee.x = snappedOffsetX
        }
    }
}
