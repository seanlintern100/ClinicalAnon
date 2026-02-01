//
//  RingBuffer.swift
//  ClinicalAnon
//
//  Purpose: Thread-safe circular buffer for audio sample storage
//  Used by AECProcessor to buffer reference audio for echo cancellation
//

import Foundation

/// Thread-safe circular buffer for audio samples
final class RingBuffer<T: Numeric> {

    private var buffer: [T]
    private var writeIndex: Int = 0
    private var readIndex: Int = 0
    private var count: Int = 0
    private let capacity: Int
    private let lock = NSLock()

    /// Initialize with specified capacity
    /// - Parameter capacity: Maximum number of elements the buffer can hold
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = [T](repeating: 0 as! T, count: capacity)
    }

    /// Number of elements currently in the buffer
    var availableCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    /// Whether the buffer is empty
    var isEmpty: Bool {
        return availableCount == 0
    }

    /// Whether the buffer is full
    var isFull: Bool {
        return availableCount == capacity
    }

    /// Write samples to the buffer
    /// - Parameters:
    ///   - samples: Pointer to samples to write
    ///   - count: Number of samples to write
    /// - Returns: Number of samples actually written
    @discardableResult
    func write(_ samples: UnsafePointer<T>, count: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let samplesToWrite = min(count, capacity - self.count)

        for i in 0..<samplesToWrite {
            buffer[writeIndex] = samples[i]
            writeIndex = (writeIndex + 1) % capacity
        }

        self.count += samplesToWrite
        return samplesToWrite
    }

    /// Write samples from an array to the buffer
    /// - Parameter samples: Array of samples to write
    /// - Returns: Number of samples actually written
    @discardableResult
    func write(_ samples: [T]) -> Int {
        return samples.withUnsafeBufferPointer { ptr in
            guard let baseAddress = ptr.baseAddress else { return 0 }
            return write(baseAddress, count: samples.count)
        }
    }

    /// Read samples from the buffer
    /// - Parameters:
    ///   - output: Pointer to write samples to
    ///   - count: Maximum number of samples to read
    /// - Returns: Number of samples actually read
    @discardableResult
    func read(_ output: UnsafeMutablePointer<T>, count: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let samplesToRead = min(count, self.count)

        for i in 0..<samplesToRead {
            output[i] = buffer[readIndex]
            readIndex = (readIndex + 1) % capacity
        }

        self.count -= samplesToRead
        return samplesToRead
    }

    /// Read samples from the buffer into an array
    /// - Parameter count: Maximum number of samples to read
    /// - Returns: Array of samples read
    func read(count: Int) -> [T] {
        var output = [T](repeating: 0 as! T, count: count)
        let actualCount = output.withUnsafeMutableBufferPointer { ptr in
            guard let baseAddress = ptr.baseAddress else { return 0 }
            return read(baseAddress, count: count)
        }
        return Array(output.prefix(actualCount))
    }

    /// Peek at samples without removing them
    /// - Parameters:
    ///   - output: Pointer to write samples to
    ///   - count: Maximum number of samples to peek
    /// - Returns: Number of samples actually peeked
    @discardableResult
    func peek(_ output: UnsafeMutablePointer<T>, count: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let samplesToPeek = min(count, self.count)
        var index = readIndex

        for i in 0..<samplesToPeek {
            output[i] = buffer[index]
            index = (index + 1) % capacity
        }

        return samplesToPeek
    }

    /// Clear all samples from the buffer
    func clear() {
        lock.lock()
        defer { lock.unlock() }

        writeIndex = 0
        readIndex = 0
        count = 0
    }

    /// Skip (discard) samples from the buffer
    /// - Parameter count: Number of samples to skip
    /// - Returns: Number of samples actually skipped
    @discardableResult
    func skip(_ count: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let samplesToSkip = min(count, self.count)
        readIndex = (readIndex + samplesToSkip) % capacity
        self.count -= samplesToSkip
        return samplesToSkip
    }
}
