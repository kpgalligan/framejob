/// A least-recently-used cache of at most `limit` values: the one policy the
/// renderers' texture pools (`LayerRenderers`), the lift's pool (`LayerLift`)
/// and the grade textures' caches (`LutTextures`, `CurveTextures`,
/// `LookTextures`) each kept a copy of (#363). A hit moves its key to the
/// most-recent end; an insert past `limit` drops from the least-recent end.
///
/// Not thread-safe: the caller holds its own lock around every call.
struct LRUCache<Key: Hashable, Value> {
    let limit: Int
    private var entries: [Key: Value] = [:]
    /// Least recently used first.
    private var order: [Key] = []

    init(limit: Int) { self.limit = limit }

    /// The value at `key`, touched; nil on a miss.
    mutating func value(for key: Key) -> Value? {
        value(for: key) { _ in true }
    }

    /// The value at `key` when `accept` takes it, touched; nil on a miss or
    /// when `accept` refuses it, which leaves its place in the order alone.
    mutating func value(for key: Key, where accept: (Value) -> Bool) -> Value? {
        guard let hit = entries[key], accept(hit) else { return nil }
        touch(key)
        return hit
    }

    /// Stores `value` at `key` as the most recent, then drops the least
    /// recent while more than `limit` are held.
    mutating func insert(_ value: Value, for key: Key) {
        entries[key] = value
        touch(key)
        while order.count > limit, let oldest = order.first {
            order.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }

    /// Drops every value.
    mutating func removeAll() {
        entries = [:]
        order = []
    }

    /// Moves `key` to the most-recent end.
    private mutating func touch(_ key: Key) {
        if let index = order.firstIndex(of: key) { order.remove(at: index) }
        order.append(key)
    }
}
