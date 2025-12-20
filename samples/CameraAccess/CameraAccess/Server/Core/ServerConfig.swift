import Foundation

/// Configuration for the ASG (AugmentOS Smart Glasses) server
public struct ServerConfig {
    /// Server port (default: 8089)
    public let port: UInt16
    
    /// Server name for identification
    public let serverName: String
    
    /// Whether CORS is enabled for cross-origin requests
    public let corsEnabled: Bool
    
    /// Maximum file size allowed (50MB default)
    public let maxFileSize: Int
    
    /// Rate limit: max requests per time window
    public let maxRequestsPerWindow: Int
    
    /// Rate limit time window in seconds
    public let rateLimitWindowSeconds: TimeInterval
    
    /// Cache size limit (max files in memory cache)
    public let cacheSizeLimit: Int
    
    /// Socket timeout for large file transfers (5 minutes default)
    public let socketTimeoutSeconds: TimeInterval
    
    public init(
        port: UInt16 = 8089,
        serverName: String = "ASG Camera Server",
        corsEnabled: Bool = true,
        maxFileSize: Int = 50 * 1024 * 1024, // 50MB
        maxRequestsPerWindow: Int = 100,
        rateLimitWindowSeconds: TimeInterval = 60,
        cacheSizeLimit: Int = 10,
        socketTimeoutSeconds: TimeInterval = 300
    ) {
        self.port = port
        self.serverName = serverName
        self.corsEnabled = corsEnabled
        self.maxFileSize = maxFileSize
        self.maxRequestsPerWindow = maxRequestsPerWindow
        self.rateLimitWindowSeconds = rateLimitWindowSeconds
        self.cacheSizeLimit = cacheSizeLimit
        self.socketTimeoutSeconds = socketTimeoutSeconds
    }
    
    /// Default configuration
    public static let `default` = ServerConfig()
}
