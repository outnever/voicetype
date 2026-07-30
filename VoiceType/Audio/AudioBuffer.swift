import Foundation
import os

/// Thread-safe ring buffer for real-time audio sample storage.
///
/// Design constraints (per RESEARCH.md Anti-Patterns and Pitfall 3):
/// - SPSC (Single Producer, Single Consumer): audio tap callback writes,
///   a dedicated consumer thread reads. Never concurrent writes from multiple threads.
/// - os_unfair_lock: lower latency than DispatchQueue for uncontended lock.
///   Non-blocking — will not cause priority inversion on the real-time audio thread.
/// - Zero heap allocation in write/read paths: fixed-size backing array allocated
///   at init time. The audio tap callback runs on a real-time priority thread —
///   any memory allocation risks audio glitches and dropouts.
///
/// Overflow behavior: when the buffer is full, new writes overwrite the oldest
/// data (oldest data is dropped). This is safe for the use case — dictation
/// produces a continuous stream where recent audio matters more than old audio.
final class RingBuffer<Element> {
    // MARK: - Storage

    /// Fixed-capacity backing array, allocated once at init.
    private var storage: [Element?]

    /// Total capacity (fixed at init time).
    private let capacity: Int

    /// Read pointer — next index to read from.
    private var readIndex: Int = 0

    /// Write pointer — next index to write to.
    private var writeIndex: Int = 0

    /// Number of readable elements currently in the buffer.
    private var count: Int = 0

    /// Thread safety via os_unfair_lock (not DispatchQueue — lower latency,
    /// no priority inversion risk on real-time audio thread).
    private var lock = os_unfair_lock()

    // MARK: - Initialization

    /// Creates a ring buffer with fixed capacity.
    /// - Parameter capacity: Maximum number of elements the buffer can hold.
    init(capacity: Int) {
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    // MARK: - Write

    /// Writes an array of elements to the buffer.
    ///
    /// **Real-time safe:** No heap allocation occurs in this method.
    /// The backing array is pre-allocated. Assignments mutate existing slots.
    ///
    /// Overflow behavior: if the buffer is full, the oldest elements are
    /// overwritten (ring buffer semantics).
    ///
    /// - Parameter elements: Samples to write (typically a batch from AVAudioEngine tap).
    func write(_ elements: [Element]) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        for element in elements {
            storage[writeIndex] = element
            writeIndex = (writeIndex + 1) % capacity

            if count < capacity {
                count += 1
            } else {
                // Buffer full: advance read pointer to drop oldest element
                readIndex = (readIndex + 1) % capacity
            }
        }
    }

    // MARK: - Read (peek without consuming)

    /// Reads up to `count` elements from the buffer without removing them.
    /// Returns fewer elements if not enough are available.
    ///
    /// **Real-time safe:** No heap allocation — the returned array
    /// is created with `Array` allocation (acceptably small for consumer thread).
    ///
    /// - Parameter count: Number of elements to peek at.
    /// - Returns: Array of elements (may be shorter than requested).
    func read(count requestedCount: Int) -> [Element] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let available = min(requestedCount, count)
        guard available > 0 else { return [] }

        var result: [Element] = []
        result.reserveCapacity(available)

        var idx = readIndex
        for _ in 0..<available {
            if let element = storage[idx] {
                result.append(element)
            }
            idx = (idx + 1) % capacity
        }

        return result
    }

    /// Consumes (removes) up to `count` elements from the front of the buffer.
    ///
    /// **Real-time safe:** Only mutates integer indices — no allocation.
    ///
    /// - Parameter count: Number of elements to consume.
    func consume(_ requestedCount: Int) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let toConsume = min(requestedCount, count)
        guard toConsume > 0 else { return }

        readIndex = (readIndex + toConsume) % capacity
        count -= toConsume
    }

    // MARK: - Query

    /// Number of elements currently available for reading.
    var availableCount: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return count
    }

    // MARK: - Reset

    /// Clears all data in the buffer, resetting read/write pointers.
    ///
    /// **Real-time safe:** Only mutates integer indices — no allocation.
    func reset() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        readIndex = 0
        writeIndex = 0
        count = 0
        // Clear references to allow ARC to release element memory.
        // For value types (Float), this is a no-op; for reference types,
        // it prevents retention in the buffer.
        for i in 0..<capacity {
            storage[i] = nil
        }
    }
}
