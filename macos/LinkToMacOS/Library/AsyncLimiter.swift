import Foundation

/// 限制同时进行的请求数。后来的请求优先（用户滚动时，最新进入屏幕的缩略图最重要）。
actor AsyncLimiter {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if let next = waiters.popLast() {
            next.resume()
        } else {
            running -= 1
        }
    }
}
