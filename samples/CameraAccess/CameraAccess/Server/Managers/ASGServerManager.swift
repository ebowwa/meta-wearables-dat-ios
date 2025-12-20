import Foundation

/// Manager for the ASG Camera Server
/// Handles lifecycle management and integration with the app
public final class ASGServerManager {
    
    // MARK: - Singleton
    
    public static let shared = ASGServerManager()
    
    // MARK: - Properties
    
    /// The camera server instance
    public private(set) var cameraServer: ASGCameraServer?
    
    /// Whether the server is currently running
    public var isRunning: Bool {
        return cameraServer?.isRunning ?? false
    }
    
    /// The server URL for external access
    public var serverURL: String? {
        return cameraServer?.serverURL
    }
    
    /// Server configuration
    private var config: ServerConfig = .default
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Server Lifecycle
    
    /// Configure the server before starting
    public func configure(with config: ServerConfig) {
        self.config = config
    }
    
    /// Start the camera server
    /// - Parameters:
    ///   - delegate: Delegate for handling camera events
    ///   - photosDirectory: Optional custom photos directory
    /// - Returns: True if server started successfully
    @discardableResult
    public func startServer(
        delegate: ASGCameraServerDelegate? = nil,
        photosDirectory: URL? = nil
    ) -> Bool {
        guard cameraServer == nil else {
            print("⚠️ Server already running")
            return true
        }
        
        let server = ASGCameraServer(
            config: config,
            photosDirectory: photosDirectory
        )
        server.delegate = delegate
        
        do {
            try server.start()
            cameraServer = server
            
            if let url = server.serverURL {
                print("✅ ASG Server started at: \(url)")
            }
            
            return true
        } catch {
            print("❌ Failed to start server: \(error)")
            return false
        }
    }
    
    /// Stop the camera server
    public func stopServer() {
        cameraServer?.stop()
        cameraServer = nil
        print("🛑 ASG Server stopped")
    }
    
    /// Restart the server
    public func restartServer(delegate: ASGCameraServerDelegate? = nil) {
        let wasRunning = isRunning
        let existingDelegate = cameraServer?.delegate
        let photosDir = cameraServer?.photosDirectory
        
        stopServer()
        
        if wasRunning {
            startServer(
                delegate: delegate ?? existingDelegate,
                photosDirectory: photosDir
            )
        }
    }
    
    // MARK: - Photo Management
    
    /// Save a photo to the server's gallery
    public func savePhoto(_ data: Data, named: String? = nil) -> URL? {
        return cameraServer?.savePhoto(data, named: named)
    }
    
    /// Save a video to the server's gallery
    public func saveVideo(from sourceURL: URL, named: String? = nil) -> URL? {
        return cameraServer?.saveVideo(from: sourceURL, named: named)
    }
    
    /// Update the latest photo for live preview
    public func updateLatestPhoto(_ data: Data) {
        cameraServer?.updateLatestPhoto(data)
    }
}

// MARK: - SwiftUI Integration

import SwiftUI

/// View modifier to start/stop the server with the view lifecycle
public struct ASGServerViewModifier: ViewModifier {
    let delegate: ASGCameraServerDelegate?
    let autoStart: Bool
    
    public init(delegate: ASGCameraServerDelegate? = nil, autoStart: Bool = true) {
        self.delegate = delegate
        self.autoStart = autoStart
    }
    
    public func body(content: Content) -> some View {
        content
            .onAppear {
                if autoStart {
                    ASGServerManager.shared.startServer(delegate: delegate)
                }
            }
            .onDisappear {
                // Optionally stop on disappear
                // ASGServerManager.shared.stopServer()
            }
    }
}

extension View {
    /// Add ASG Camera Server to this view
    public func withASGServer(delegate: ASGCameraServerDelegate? = nil, autoStart: Bool = true) -> some View {
        modifier(ASGServerViewModifier(delegate: delegate, autoStart: autoStart))
    }
}
