# Photos API Callback Analysis

## Question 1: Does HybridAssetLoader NEED actor protection?

### HybridAssetLoader Mutable State:
- `private var cancelled = false` - single boolean flag
- All other properties are `let` (immutable)

### Old PlaybackPreparationCoordinator (regular class, WORKS):
- `private var cache: [Int: CachedContext] = [:]` - mutable dictionary
- `private var currentTask: Task<Void, Never>?` - mutable optional
- `private var sourceTape: Tape?` - mutable optional
- `private var clips: [Clip] = []` - mutable array

**ANSWER: NO** - HybridAssetLoader has LESS mutable state than the old coordinator. The old one worked fine as a regular class with MORE state. Actor protection is unnecessary here.

## Question 2: Photos Authorization/Threading Issues?

### Authorization:
- ✅ Check exists: `PHPhotoLibrary.authorizationStatus(for: .readWrite)`
- ✅ Checks for `.authorized` or `.limited`
- ✅ Would throw error if unauthorized (logs would show it)

### Threading Pattern Comparison:

**Old Working Code (TapeExporter):**
```swift
let sema = DispatchSemaphore(value: 0)
var result: AVAsset?
PHImageManager.default().requestAVAsset(forVideo: ph, options: opts) { asset, _, _ in
    result = asset; sema.signal()  // Callback on background thread
}
_ = sema.wait(timeout: .now() + 20)  // Blocks calling thread
return result
```
- Synchronous, blocking - no actor isolation
- Callback executes freely on whatever thread Photos API chooses

**New Code:**
```swift
return try await withCheckedThrowingContinuation { continuation in
    PHImageManager.default().requestAVAsset(...) { asset, _, info in
        continuation.resume(returning: asset)  // Callback tries to resume continuation
    }
}
```
- Async continuation - but created in actor context
- When continuation created inside actor method, callback might be blocked

**ANSWER: The issue is ACTOR ISOLATION, not authorization.** The continuation is created while waiting on the actor, so Photos callback can't resume it properly.

## Question 3: Test Simple Photos API Call?

**RECOMMENDATION: YES** - Create minimal test to verify Photos API works outside actor context.

## Root Cause Confirmed:

The problem is **actor serialization blocking Photos callbacks**. When:
1. `Task.detached` calls `self.resolvePhotosAsset()` (actor method)
2. Swift serializes this back to the actor
3. Continuation created while waiting on actor
4. Photos callback fires on background thread
5. Callback tries to resume continuation
6. **BLOCKED** - can't resume continuation that's waiting on actor

## Solution:

Convert `HybridAssetLoader` from `actor` to regular `class` - matches old working pattern exactly.

