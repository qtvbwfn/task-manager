import Foundation

/// 固定容量环形缓冲：追加即覆盖最旧值，读取返回按时间顺序排列的值。
struct RingBuffer<Element> {
    private var storage: [Element?]
    private var writeIndex = 0
    private(set) var count = 0

    var capacity: Int { storage.count }

    init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer capacity must be positive")
        storage = Array(repeating: nil, count: capacity)
    }

    mutating func append(_ value: Element) {
        storage[writeIndex] = value
        writeIndex = (writeIndex + 1) % storage.count
        if count < storage.count { count += 1 }
    }

    var values: [Element] {
        guard count > 0 else { return [] }
        if count < storage.count {
            return storage[0..<count].compactMap { $0 }
        }
        let tail = storage[writeIndex...]
        let head = storage[..<writeIndex]
        return (tail + head).compactMap { $0 }
    }

    mutating func removeAll() {
        storage = Array(repeating: nil, count: storage.count)
        writeIndex = 0
        count = 0
    }
}