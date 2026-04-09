import Foundation
import os

/// Thread-safe flag that can only be set once. Returns `true` on the first call to `testAndSet()`.
final class AtomicFlag: @unchecked Sendable {
    private let lock = os_unfair_lock_t.allocate(capacity: 1)
    private var flag = false

    init() { lock.initialize(to: os_unfair_lock()) }

    deinit { lock.deallocate() }

    /// Returns `true` the first time it's called; `false` on all subsequent calls.
    func testAndSet() -> Bool {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        if flag { return false }
        flag = true
        return true
    }
}

/// Minimal sendable wrapper for passing a mutable value across concurrency boundaries.
final class UnsafeSendableBox<T>: @unchecked Sendable {
    var value: T?
}
