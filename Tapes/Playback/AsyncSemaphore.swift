import Foundation

/// A semaphore for controlling concurrency in async/await contexts
final class AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    init(count: Int) {
        self.count = count
    }
    
    func wait() async {
        if count > 0 {
            count -= 1
            return
        }
        
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
    
    func signal() {
        if let waiter = waiters.popFirst() {
            waiter.resume()
        } else {
            count += 1
        }
    }
}

extension Array {
    mutating func popFirst() -> Element? {
        guard !isEmpty else { return nil }
        return removeFirst()
    }
}

