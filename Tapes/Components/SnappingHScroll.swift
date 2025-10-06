import SwiftUI

/// A horizontal scroll container that snaps so the *gap between items* aligns with the visual center.
struct SnappingHScroll<Content: View>: UIViewRepresentable {
    let itemWidth: CGFloat
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    let containerWidth: CGFloat
    let targetSnapIndex: Int?
    let currentSnapIndex: Int
    let pendingToken: UUID?
    let tapeId: UUID
    let onSnapped: ((Int, Int) -> Void)?
    let content: () -> Content

    init(itemWidth: CGFloat,
         leadingInset: CGFloat = 16,
         trailingInset: CGFloat = 16,
         containerWidth: CGFloat,
         targetSnapIndex: Int? = nil,
         currentSnapIndex: Int = 1,
         pendingToken: UUID? = nil,
         tapeId: UUID,
         onSnapped: ((Int, Int) -> Void)? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.itemWidth = itemWidth
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
        self.containerWidth = containerWidth
        self.targetSnapIndex = targetSnapIndex
        self.currentSnapIndex = currentSnapIndex
        self.pendingToken = pendingToken
        self.tapeId = tapeId
        self.onSnapped = onSnapped
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
        context.coordinator.updateCurrentSnapIndex(currentSnapIndex)

        DispatchQueue.main.async {
            self.setInitialPosition(scrollView: scrollView)
            if let targetIndex = self.targetSnapIndex {
                self.performProgrammaticScroll(scrollView: scrollView, targetIndex: targetIndex, retryCount: 0)
            }
        }

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        // No-op; SwiftUI content updates through hosting controller automatically.
    }
    
    private func performProgrammaticScroll(scrollView: UIScrollView, targetIndex: Int, retryCount: Int) {
        let maxRetries = 5
        let retryDelay: TimeInterval = 0.1
        
        // Check if layout is ready
        if scrollView.contentSize.width > 0 && scrollView.bounds.width > 0 {
            // Check token validity to prevent stale applies
            if pendingToken != nil {
                // Calculate target position
                let targetX = leadingInset + CGFloat(targetIndex) * itemWidth - containerWidth / 2.0
                let maxOffsetX = max(0, scrollView.contentSize.width - containerWidth)
                let clampedTargetX = min(max(targetX, 0), maxOffsetX)
                
                // Set programmatic scroll flag to prevent feedback
                if let coordinator = scrollView.delegate as? Coordinator {
                    coordinator.isProgrammaticScroll = true
                    coordinator.updateCurrentSnapIndex(targetIndex)
                }
                
                // Perform the scroll
                scrollView.setContentOffset(CGPoint(x: clampedTargetX, y: 0), animated: true)
            } else {
                TapesLog.ui.warning("SnappingHScroll token mismatch for tape \(tapeId)")
            }
            
        } else if retryCount < maxRetries {
            DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                self.performProgrammaticScroll(scrollView: scrollView, targetIndex: targetIndex, retryCount: retryCount + 1)
            }
        } else {
            TapesLog.ui.error("SnappingHScroll failed to perform programmatic scroll after \(maxRetries) retries")
        }
    }
    
    /// Set the initial position to avoid flash
    private func setInitialPosition(scrollView: UIScrollView) {
        // Set the scroll view to the current position immediately
        let currentPosition = currentSnapIndex
        let currentX = leadingInset + CGFloat(currentPosition) * itemWidth - containerWidth / 2.0
        let maxOffsetX = max(0, scrollView.contentSize.width - containerWidth)
        let clampedCurrentX = min(max(currentX, 0), maxOffsetX)
        
        scrollView.setContentOffset(CGPoint(x: clampedCurrentX, y: 0), animated: false)
    }
    
    /// Get the current carousel position based on scroll offset
    private func getCurrentCarouselPosition(scrollView: UIScrollView) -> Int {
        let currentOffset = scrollView.contentOffset.x
        let centerX = containerWidth / 2.0
        let adjustedOffset = currentOffset + centerX
        let position = (adjustedOffset - leadingInset) / itemWidth
        return max(0, Int(round(position)))
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: SnappingHScroll
        weak var hostingController: UIHostingController<HStack<Content>>?
        weak var scrollView: UIScrollView?
        
        // State machine for position tracking
        enum CarouselState {
            case idle
            case scrolling
            case snapping
            case settling
        }
        
        private var state: CarouselState = .idle
        private var currentSnapIndex: Int = 1 // Will be updated with actual position
        private var isUserScrolling: Bool = false
        var isProgrammaticScroll: Bool = false

        // We need to know total content width (calculated on the fly)
        init(parent: SnappingHScroll) {
            self.parent = parent
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // Update state based on scroll behavior
            if isUserScrolling {
                state = .scrolling
                isProgrammaticScroll = false // Reset programmatic scroll flag when user starts scrolling
            } else if state == .scrolling {
                state = .snapping
            }
        }
        
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isUserScrolling = true
            isProgrammaticScroll = false // Reset programmatic scroll flag when user starts dragging
            state = .scrolling
        }
        
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            isUserScrolling = false
            if !decelerate {
                // User stopped dragging and there's no deceleration
                state = .settling
                updatePositionIfValid()
            }
        }
        
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            state = .settling
            updatePositionIfValid()
        }
        
        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            state = .idle
            if isProgrammaticScroll {
                isProgrammaticScroll = false // Reset programmatic scroll flag after animation completes
            }
            updatePositionIfValid()
        }
        
        private func updatePositionIfValid() {
            guard state == .idle || state == .settling,
                  isValidSnapIndex(currentSnapIndex) else { return }
            
            // Only update position when carousel is truly at rest
            if let onSnapped = parent.onSnapped {
                let leftIndex = currentSnapIndex
                let rightIndex = leftIndex + 1
                onSnapped(leftIndex, rightIndex)
            }
        }
        
        private func isValidSnapIndex(_ index: Int) -> Bool {
            // Basic validation - can be enhanced with content size checks
            return index >= 0
        }
        
        func updateCurrentSnapIndex(_ index: Int) {
            currentSnapIndex = index
            isProgrammaticScroll = true
        }

        func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                       withVelocity velocity: CGPoint,
                                       targetContentOffset: UnsafeMutablePointer<CGPoint>) {

            guard parent.itemWidth > 0 else { 
                TapesLog.ui.error("SnappingHScroll received non-positive item width")
                return 
            }

            // If this is a programmatic scroll, don't override the target position
            if isProgrammaticScroll {
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
            // Assign final target
            targetContentOffset.pointee.x = snappedOffsetX
            
            // Update current snap index for state machine
            currentSnapIndex = Int(n)
            
            // Don't call onSnapped here - let the state machine handle it
            // when the carousel is truly at rest
        }
    }
}
