import Foundation
import AVFoundation
import os
import Network

/// Manages background loading of remaining assets after initial window
actor BackgroundAssetService {
    
    // MARK: - Types
    
    enum Priority: Int, Comparable {
        case low = 0
        case normal = 1
        case high = 2
        
        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    struct LoadTask {
        let clipIndex: Int
        let clip: Clip
        let priority: Priority
        let deadline: Date?
    }
    
    // MARK: - Properties
    
    private let loader: HybridAssetLoader
    private var queue: [LoadTask] = []
    private var activeTasks: Set<Int> = []
    private var completedAssets: [Int: HybridAssetLoader.ResolvedAsset] = [:]
    private var failedAssets: [Int: Error] = [:]
    
    private let maxConcurrentFetches: Int
    private var isPaused = false
    private var isCancelled = false
    
    // Network monitoring
    private let networkMonitor = NWPathMonitor()
    private var isCellular = false
    
    // MARK: - Initialization
    
    init(
        loader: HybridAssetLoader,
        maxConcurrentFetches: Int = 2
    ) {
        self.loader = loader
        self.maxConcurrentFetches = maxConcurrentFetches
        
        // Start network monitoring
        let queue = DispatchQueue(label: "BackgroundAssetService.network")
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                await self?.updateNetworkStatus(isCellular: path.status == .satisfied && path.isExpensive)
            }
        }
        networkMonitor.start(queue: queue)
    }
    
    // MARK: - Public API
    
    /// Enqueue assets for background loading
    func enqueue(assets: [(Int, Clip)], priority: Priority = .normal) {
        guard !isCancelled else { return }
        
        for (index, clip) in assets {
            // Skip if already loaded or failed
            guard completedAssets[index] == nil && failedAssets[index] == nil else { continue }
            
            // Skip if already in queue
            guard !queue.contains(where: { $0.clipIndex == index }) else { continue }
            
            queue.append(LoadTask(
                clipIndex: index,
                clip: clip,
                priority: priority,
                deadline: nil
            ))
        }
        
        // Sort by priority (high first)
        queue.sort { $0.priority > $1.priority }
        
        TapesLog.player.info("BackgroundAssetService: Enqueued \(assets.count) assets")
        
        // Start processing if not paused
        if !isPaused {
            Task {
                await processQueueIfNeeded()
            }
        }
    }
    
    /// Get completed asset if available
    func getCompletedAsset(at index: Int) -> HybridAssetLoader.ResolvedAsset? {
        return completedAssets[index]
    }
    
    /// Get all completed assets
    func getAllCompletedAssets() -> [(Int, HybridAssetLoader.ResolvedAsset)] {
        return Array(completedAssets).sorted { $0.key < $1.key }
    }
    
    /// Pause loading (e.g., on memory warning)
    func pause() {
        isPaused = true
        TapesLog.player.info("BackgroundAssetService: Paused")
    }
    
    /// Resume loading
    func resume() {
        isPaused = false
        TapesLog.player.info("BackgroundAssetService: Resumed")
        Task {
            await processQueueIfNeeded()
        }
    }
    
    /// Cancel all loading
    func cancel() {
        isCancelled = true
        queue.removeAll()
        activeTasks.removeAll()
        TapesLog.player.info("BackgroundAssetService: Cancelled")
    }
    
    // MARK: - Private Implementation
    
    private func processQueueIfNeeded() async {
        guard !isCancelled && !isPaused else { return }
        guard activeTasks.count < maxConcurrentFetches else { return }
        guard let nextTask = queue.first else { return }
        
        // Remove from queue
        queue.removeFirst()
        activeTasks.insert(nextTask.clipIndex)
        
        TapesLog.player.info("BackgroundAssetService: Processing clip \(nextTask.clipIndex) (active: \(self.activeTasks.count))")
        
        // Load asset
        Task {
            do {
                // Use builder directly to resolve asset (loader.loadWindow is for batch)
                let builder = TapeCompositionBuilder()
                let context = try await builder.resolveClipContext(for: nextTask.clip, index: nextTask.clipIndex)
                
                // Convert to ResolvedAsset
                let resolvedAsset = HybridAssetLoader.ResolvedAsset(
                    clipIndex: nextTask.clipIndex,
                    asset: context.asset,
                    clip: nextTask.clip,
                    duration: context.duration,
                    naturalSize: context.naturalSize,
                    preferredTransform: context.preferredTransform,
                    hasAudio: context.hasAudio,
                    isTemporary: context.isTemporaryAsset,
                    motionEffect: context.motionEffect
                )
                
                await self.assetCompleted(index: nextTask.clipIndex, asset: resolvedAsset)
            } catch {
                await self.assetFailed(index: nextTask.clipIndex, error: error)
            }
            
            // Remove from active tasks
            activeTasks.remove(nextTask.clipIndex)
            
            // Process next item
            await processQueueIfNeeded()
        }
    }
    
    private func assetCompleted(index: Int, asset: HybridAssetLoader.ResolvedAsset) {
        completedAssets[index] = asset
        TapesLog.player.info("BackgroundAssetService: Clip \(index) loaded in background")
    }
    
    private func assetFailed(index: Int, error: Error) {
        failedAssets[index] = error
        TapesLog.player.warning("BackgroundAssetService: Clip \(index) failed: \(error.localizedDescription)")
    }
    
    private func updateNetworkStatus(isCellular: Bool) {
        self.isCellular = isCellular
        if isCellular {
            // Reduce concurrency on cellular
            maxConcurrentFetches = 1
        } else {
            maxConcurrentFetches = 2
        }
    }
}

