import SwiftUI
import UIKit

private class SnapCollectionView: UICollectionView {
    var onFirstLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        if let action = onFirstLayout {
            onFirstLayout = nil
            action()
        }
    }
}

struct SnappingCarouselView<CellContent: View>: UIViewRepresentable {
    let itemWidth: CGFloat
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    let containerWidth: CGFloat
    let targetSnapIndex: Int?
    let currentSnapIndex: Int
    let pendingToken: UUID?
    let tapeId: UUID
    let onSnapped: ((Int, Int) -> Void)?
    var isLongPressEnabled: Bool = false
    var onJiggleRequested: (() -> Void)? = nil
    var onItemLongPressStarted: ((Int, CGPoint, CGRect) -> Bool)? = nil
    var onDragPositionChanged: ((CGPoint) -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil
    var onScrollFractionChanged: ((CGFloat) -> Void)? = nil
    let items: [CarouselItem]
    let contentVersion: Int
    let cellContent: (CarouselItem) -> CellContent
    var onPlusFramesChanged: ((CGRect?, CGRect?) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: leadingInset, bottom: 0, right: trailingInset)

        let cv = SnapCollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.clipsToBounds = false
        cv.decelerationRate = .fast
        cv.delegate = context.coordinator
        cv.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")

        let coordinator = context.coordinator
        let dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: cv) {
            [weak coordinator] collectionView, indexPath, itemId -> UICollectionViewCell? in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
            guard let coordinator,
                  let item = coordinator.currentItems.first(where: { $0.id == itemId })
            else { return cell }
            cell.contentConfiguration = UIHostingConfiguration {
                coordinator.parent.cellContent(item)
            }
            .margins(.all, 0)
            cell.clipsToBounds = false
            cell.contentView.clipsToBounds = false
            return cell
        }

        coordinator.dataSource = dataSource
        coordinator.collectionView = cv
        coordinator.currentItems = items
        coordinator.currentItemIds = items.map(\.id)
        coordinator.lastContentVersion = contentVersion
        coordinator.updateCurrentSnapIndex(currentSnapIndex)

        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(items.map(\.id))
        dataSource.apply(snapshot, animatingDifferences: false)

        let snapIndex = currentSnapIndex
        let target = targetSnapIndex
        cv.onFirstLayout = { [weak cv, weak coordinator] in
            guard let cv, let coordinator else { return }
            coordinator.isUpdatingView = true
            defer { coordinator.isUpdatingView = false }
            self.setPosition(collectionView: cv, snapIndex: snapIndex, animated: false)
            if let target {
                self.performProgrammaticScroll(
                    collectionView: cv, targetIndex: target,
                    retryCount: 0, coordinator: coordinator
                )
            }
        }

        let jigglePress = UILongPressGestureRecognizer(
            target: coordinator,
            action: #selector(Coordinator.handleJigglePress(_:))
        )
        jigglePress.minimumPressDuration = 0.3
        jigglePress.delegate = coordinator
        jigglePress.isEnabled = !isLongPressEnabled
        cv.addGestureRecognizer(jigglePress)
        coordinator.jigglePressGesture = jigglePress

        let longPress = UILongPressGestureRecognizer(
            target: coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.3
        longPress.delegate = coordinator
        longPress.isEnabled = isLongPressEnabled
        cv.addGestureRecognizer(longPress)
        coordinator.longPressGesture = longPress

        return cv
    }

    func updateUIView(_ uiView: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isUpdatingView = true
        defer { coordinator.isUpdatingView = false }

        coordinator.parent = self
        coordinator.longPressGesture?.isEnabled = isLongPressEnabled
        coordinator.jigglePressGesture?.isEnabled = !isLongPressEnabled

        let oldIds = coordinator.currentItemIds
        let newIds = items.map(\.id)
        coordinator.currentItems = items
        coordinator.currentItemIds = newIds

        let idsChanged = oldIds != newIds
        let versionChanged = coordinator.lastContentVersion != contentVersion
        coordinator.lastContentVersion = contentVersion

        if idsChanged {
            var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.appendSections([0])
            snapshot.appendItems(newIds)
            coordinator.dataSource?.apply(snapshot, animatingDifferences: false)

            uiView.collectionViewLayout.invalidateLayout()
            uiView.layoutIfNeeded()

            let snap = currentSnapIndex
            coordinator.updateCurrentSnapIndex(snap)
            setPosition(collectionView: uiView, snapIndex: snap, animated: false)
        } else if versionChanged {
            var snapshot = coordinator.dataSource?.snapshot()
                ?? NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.reconfigureItems(snapshot.itemIdentifiers)
            coordinator.dataSource?.apply(snapshot, animatingDifferences: false)
        }

        if let target = targetSnapIndex,
           target != coordinator.lastAppliedTarget {
            coordinator.lastAppliedTarget = target
            DispatchQueue.main.async {
                self.performProgrammaticScroll(
                    collectionView: uiView, targetIndex: target,
                    retryCount: 0, coordinator: coordinator
                )
            }
        }
    }

    // MARK: - Scroll helpers

    private func setPosition(collectionView: UICollectionView, snapIndex: Int, animated: Bool) {
        let targetX = leadingInset + CGFloat(snapIndex) * itemWidth - containerWidth / 2.0
        let maxX = max(0, collectionView.contentSize.width - containerWidth)
        let clampedX = min(max(targetX, 0), maxX)
        collectionView.setContentOffset(CGPoint(x: clampedX, y: 0), animated: animated)
    }

    private func performProgrammaticScroll(
        collectionView: UICollectionView,
        targetIndex: Int,
        retryCount: Int,
        coordinator: Coordinator
    ) {
        let maxRetries = 5
        let retryDelay: TimeInterval = 0.1
        let token = pendingToken

        if collectionView.contentSize.width > 0 && collectionView.bounds.width > 0 {
            guard token != nil else {
                TapesLog.ui.warning("SnappingCarouselView token mismatch for tape \(tapeId)")
                return
            }

            let targetX = leadingInset + CGFloat(targetIndex) * itemWidth - containerWidth / 2.0
            let maxX = max(0, collectionView.contentSize.width - containerWidth)
            let clampedX = min(max(targetX, 0), maxX)

            coordinator.isProgrammaticScroll = true
            coordinator.updateCurrentSnapIndex(targetIndex)
            collectionView.setContentOffset(CGPoint(x: clampedX, y: 0), animated: true)
        } else if retryCount < maxRetries {
            DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak collectionView] in
                guard let collectionView, token == self.pendingToken else { return }
                self.performProgrammaticScroll(
                    collectionView: collectionView, targetIndex: targetIndex,
                    retryCount: retryCount + 1, coordinator: coordinator
                )
            }
        } else {
            TapesLog.ui.error(
                "SnappingCarouselView programmatic scroll failed after \(maxRetries) retries"
            )
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate {
        var parent: SnappingCarouselView
        var dataSource: UICollectionViewDiffableDataSource<Int, String>?
        weak var collectionView: UICollectionView?
        weak var longPressGesture: UILongPressGestureRecognizer?
        weak var jigglePressGesture: UILongPressGestureRecognizer?
        var currentItems: [CarouselItem] = []
        var currentItemIds: [String] = []
        var lastContentVersion: Int = 0
        var lastAppliedTarget: Int?
        var isUpdatingView = false
        private var isDragging = false
        private var lastFractionReportTime: CFTimeInterval = 0
        private var isUserScrolling: Bool = false
        var isProgrammaticScroll: Bool = false
        private var currentSnapIndex: Int = 1
        private var lastReportedStartFrame: CGRect?
        private var lastReportedEndFrame: CGRect?

        init(parent: SnappingCarouselView) {
            self.parent = parent
        }

        // MARK: - Flow Layout

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            CGSize(width: parent.itemWidth, height: max(1, collectionView.bounds.height))
        }

        // MARK: - Jiggle mode entry

        @objc func handleJigglePress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.impactOccurred()
            parent.onJiggleRequested?()
        }

        // MARK: - Long press drag handling

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let collectionView else { return }

            switch gesture.state {
            case .began:
                let point = gesture.location(in: collectionView)
                guard let indexPath = collectionView.indexPathForItem(at: point),
                      let cell = collectionView.cellForItem(at: indexPath) else { return }

                let itemIndex = indexPath.item
                let globalFrame = collectionView.convert(cell.frame, to: nil)
                let globalPos = gesture.location(in: nil)

                let didLift = parent.onItemLongPressStarted?(itemIndex, globalPos, globalFrame) ?? false
                if didLift {
                    isDragging = true
                    collectionView.isScrollEnabled = false
                }

            case .changed:
                if isDragging {
                    parent.onDragPositionChanged?(gesture.location(in: nil))
                }

            case .ended, .cancelled, .failed:
                if isDragging {
                    isDragging = false
                    collectionView.isScrollEnabled = true
                    parent.onDragEnded?()
                }

            default:
                break
            }
        }

        // MARK: - UIGestureRecognizerDelegate

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer !== collectionView?.panGestureRecognizer
        }

        // MARK: - Scroll View Delegate

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if isUserScrolling { isProgrammaticScroll = false }

            guard parent.itemWidth > 0 else { return }
            let now = CACurrentMediaTime()
            guard now - lastFractionReportTime >= 0.016 else { return }
            lastFractionReportTime = now

            let centerX = parent.containerWidth / 2.0
            let fraction = (scrollView.contentOffset.x + centerX - parent.leadingInset) / parent.itemWidth

            if isUpdatingView {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.parent.onScrollFractionChanged?(fraction)
                    self.reportPlusFrames()
                }
            } else {
                parent.onScrollFractionChanged?(fraction)
                reportPlusFrames()
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isUserScrolling = true
            isProgrammaticScroll = false
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            isUserScrolling = false
            if !decelerate { updatePositionIfValid() }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            updatePositionIfValid()
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            if isProgrammaticScroll { isProgrammaticScroll = false }
            updatePositionIfValid()
        }

        func scrollViewWillEndDragging(
            _ scrollView: UIScrollView,
            withVelocity velocity: CGPoint,
            targetContentOffset: UnsafeMutablePointer<CGPoint>
        ) {
            guard parent.itemWidth > 0 else { return }
            if isProgrammaticScroll { return }

            let proposedX = targetContentOffset.pointee.x
            let centerX = parent.containerWidth / 2.0
            let rawN = (proposedX + centerX - parent.leadingInset) / parent.itemWidth
            var n = round(rawN)
            if n < 0 { n = 0 }

            var snappedX = parent.leadingInset + n * parent.itemWidth - centerX
            let maxX = max(0, scrollView.contentSize.width - parent.containerWidth)
            snappedX = min(max(snappedX, 0), maxX)
            targetContentOffset.pointee.x = snappedX

            currentSnapIndex = Int(n)
        }

        // MARK: - Snap position

        private func updatePositionIfValid() {
            guard isValidSnapIndex(currentSnapIndex) else { return }
            parent.onSnapped?(currentSnapIndex, currentSnapIndex + 1)
        }

        private func isValidSnapIndex(_ index: Int) -> Bool {
            guard index >= 0 else { return false }
            guard parent.itemWidth > 0, let cv = collectionView, cv.contentSize.width > 0 else {
                return index >= 0
            }
            let maxIndex = Int(ceil(
                (cv.contentSize.width - parent.leadingInset - parent.trailingInset) / parent.itemWidth
            ))
            return index <= maxIndex
        }

        func updateCurrentSnapIndex(_ index: Int) {
            currentSnapIndex = index
            isProgrammaticScroll = true
        }

        func fireOnSnapped() {
            guard isValidSnapIndex(currentSnapIndex) else { return }
            let idx = currentSnapIndex
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isValidSnapIndex(idx) else { return }
                self.parent.onSnapped?(idx, idx + 1)
            }
        }

        // MARK: - Drop target frames

        func reportPlusFrames() {
            guard parent.isLongPressEnabled, let cv = collectionView else { return }

            let startFrame: CGRect? = cv.cellForItem(at: IndexPath(item: 0, section: 0))
                .map { cv.convert($0.frame, to: nil) }

            let lastIdx = currentItems.count - 1
            let endFrame: CGRect? = lastIdx > 0
                ? cv.cellForItem(at: IndexPath(item: lastIdx, section: 0))
                    .map { cv.convert($0.frame, to: nil) }
                : nil

            guard startFrame != lastReportedStartFrame || endFrame != lastReportedEndFrame else { return }
            lastReportedStartFrame = startFrame
            lastReportedEndFrame = endFrame
            parent.onPlusFramesChanged?(startFrame, endFrame)
        }
    }
}
