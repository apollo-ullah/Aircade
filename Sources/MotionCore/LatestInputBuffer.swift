import Foundation

/// Coalesces sensor input so a busy UI consumes the newest reading, never a backlog.
/// Session tokens keep callbacks from a stopped connection out of its replacement.
public final class LatestInputBuffer<Value> {
    private let lock = NSLock()
    private var session: UUID?
    private var latest: Value?
    public init() {}

    public func begin() -> UUID {
        lock.lock(); defer { lock.unlock() }
        let token = UUID()
        session = token; latest = nil
        return token
    }
    public func submit(_ value: Value, session token: UUID) {
        lock.lock(); defer { lock.unlock() }
        guard session == token else { return }
        latest = value
    }
    public func take() -> Value? {
        lock.lock(); defer { lock.unlock() }
        defer { latest = nil }
        return latest
    }
    public func stop() {
        lock.lock(); defer { lock.unlock() }
        session = nil; latest = nil
    }
}
