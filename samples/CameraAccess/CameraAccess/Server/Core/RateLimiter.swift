import Foundation

/// Protocol for rate limiting requests
public protocol RateLimiting {
    /// Check if a request from the given IP is allowed
    func isAllowed(ip: String) -> Bool
    
    /// Record a request from the given IP
    func recordRequest(ip: String)
    
    /// Get the maximum requests allowed per window
    var maxRequests: Int { get }
    
    /// Get the time window in seconds
    var timeWindowSeconds: TimeInterval { get }
}

/// Default implementation of rate limiter using sliding window
public final class RateLimiter: RateLimiting {
    
    private var requestCounts: [String: [Date]] = [:]
    private let lock = NSLock()
    
    public let maxRequests: Int
    public let timeWindowSeconds: TimeInterval
    
    public init(maxRequests: Int = 100, timeWindowSeconds: TimeInterval = 60) {
        self.maxRequests = maxRequests
        self.timeWindowSeconds = timeWindowSeconds
    }
    
    public func isAllowed(ip: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        cleanupOldRequests(for: ip)
        
        let count = requestCounts[ip]?.count ?? 0
        return count < maxRequests
    }
    
    public func recordRequest(ip: String) {
        lock.lock()
        defer { lock.unlock() }
        
        cleanupOldRequests(for: ip)
        
        if requestCounts[ip] == nil {
            requestCounts[ip] = []
        }
        requestCounts[ip]?.append(Date())
    }
    
    private func cleanupOldRequests(for ip: String) {
        let cutoff = Date().addingTimeInterval(-timeWindowSeconds)
        requestCounts[ip] = requestCounts[ip]?.filter { $0 > cutoff } ?? []
    }
    
    /// Clear all rate limit data
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        requestCounts.removeAll()
    }
}
