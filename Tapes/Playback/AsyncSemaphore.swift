import Foundation

/// Async/await-compatible semaphore for Swift concurrency
/// Prevents exhausting Photos API by limiting concurrent requests
final class AsyncSemaphore {
    private let maxCount: Int
    private var currentCount: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let lock = NSLock()
    
    init(value: Int) {
        self.maxCount = value
        self.currentCount = value
    }
    
    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if currentCount > 0 {
                currentCount -= 1
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }
    
    func signal() {
        lock.lock()
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            lock.unlock()
            waiter.resume()
        } else {
            currentCount = min(currentCount + 1, maxCount)
            lock.unlock()
        }
    }
}

