import Foundation

/// Protocol for managing cached data
public protocol CacheManaging {
    /// Get cached data for key
    func get(_ key: String) -> Data?
    
    /// Store data with optional TTL
    func put(_ key: String, data: Data, ttlMs: Int?)
    
    /// Remove cached data for key
    func remove(_ key: String)
    
    /// Clear all cached data
    func clear()
    
    /// Get current cache size
    var count: Int { get }
}

/// Default implementation of cache manager with LRU eviction
public final class CacheManager: CacheManaging {
    
    private struct CacheEntry {
        let data: Data
        let expiresAt: Date?
        var lastAccessed: Date
    }
    
    private var cache: [String: CacheEntry] = [:]
    private let lock = NSLock()
    private let maxEntries: Int
    
    public init(maxEntries: Int = 10) {
        self.maxEntries = maxEntries
    }
    
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }
    
    public func get(_ key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        
        guard var entry = cache[key] else {
            return nil
        }
        
        // Check expiration
        if let expiresAt = entry.expiresAt, Date() > expiresAt {
            cache.removeValue(forKey: key)
            return nil
        }
        
        // Update last accessed time
        entry.lastAccessed = Date()
        cache[key] = entry
        
        return entry.data
    }
    
    public func put(_ key: String, data: Data, ttlMs: Int? = nil) {
        lock.lock()
        defer { lock.unlock() }
        
        // Evict oldest if at capacity
        if cache.count >= maxEntries && cache[key] == nil {
            evictOldest()
        }
        
        let expiresAt: Date? = ttlMs.map { Date().addingTimeInterval(Double($0) / 1000.0) }
        
        cache[key] = CacheEntry(
            data: data,
            expiresAt: expiresAt,
            lastAccessed: Date()
        )
    }
    
    public func remove(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        cache.removeValue(forKey: key)
    }
    
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
    
    private func evictOldest() {
        // Find and remove the least recently accessed entry
        if let oldest = cache.min(by: { $0.value.lastAccessed < $1.value.lastAccessed }) {
            cache.removeValue(forKey: oldest.key)
        }
    }
}
