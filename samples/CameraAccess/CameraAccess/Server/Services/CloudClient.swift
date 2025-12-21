import Foundation
import UIKit

/// Configuration for connecting to the MentraOS Cloud Server
public struct CloudConfig {
    /// The base URL for the cloud server
    public let baseURL: URL
    
    /// WebSocket URL for real-time communication
    public var webSocketURL: URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        return components.url!
    }
    
    /// Health check endpoint
    public var healthURL: URL {
        baseURL.appendingPathComponent("health")
    }
    
    /// Default cloud configuration (LocalTunnel)
    public static let `default` = CloudConfig(
        baseURL: URL(string: "https://olive-results-train.loca.lt")!
    )
    
    /// Local development configuration
    public static let local = CloudConfig(
        baseURL: URL(string: "http://localhost:8080")!
    )
    
    public init(baseURL: URL) {
        self.baseURL = baseURL
    }
}

/// Client for communicating with the MentraOS Cloud Server
public final class CloudClient: ObservableObject {
    
    // MARK: - Properties
    
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var lastError: String?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession.shared
    
    // MARK: - Computed URLs (uses StreamingSettings dynamically)
    
    /// Current cloud base URL from settings
    private var baseURL: URL {
        StreamingSettings.shared.cloudBaseURL ?? URL(string: "https://olive-results-train.loca.lt")!
    }
    
    /// WebSocket URL for real-time communication (MentraOS uses /glasses-ws with JWT auth)
    public var webSocketURL: URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components.path = "/glasses-ws"
        // Add JWT token for authentication
        let token = StreamingSettings.shared.authToken
        if !token.isEmpty {
            components.queryItems = [URLQueryItem(name: "token", value: token)]
        }
        return components.url!
    }
    
    /// Health check endpoint
    public var healthURL: URL {
        baseURL.appendingPathComponent("health")
    }
    
    // MARK: - Singleton
    
    public static let shared = CloudClient()
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Health Check
    
    /// Check if the cloud server is reachable
    public func checkHealth() async -> Bool {
        do {
            let (data, response) = try await session.data(from: healthURL)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }
            
            // Parse health response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String {
                let healthy = status == "ok"
                print("☁️ Cloud health: \(healthy ? "✅ OK" : "❌ Error")")
                return healthy
            }
            
            return false
        } catch {
            print("☁️ Cloud health check failed: \(error)")
            lastError = error.localizedDescription
            return false
        }
    }
    
    // MARK: - WebSocket Connection
    
    /// Connect to the cloud server via WebSocket
    public func connect() {
        guard webSocketTask == nil else { return }
        
        print("☁️ Connecting to cloud: \(webSocketURL)")
        
        webSocketTask = session.webSocketTask(with: webSocketURL)
        webSocketTask?.resume()
        
        receiveMessages()
        
        // Send CONNECTION_INIT message (required by MentraOS cloud)
        // See: GlassesToCloudMessageType.CONNECTION_INIT
        let connectMessage: [String: Any] = [
            "type": "connection_init",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: connectMessage) {
            send(data: data)
        }
        
        isConnected = true
        print("☁️ Connected to cloud server")
    }
    
    /// Disconnect from the cloud server
    public func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        print("☁️ Disconnected from cloud server")
    }
    
    /// Send data to the cloud server
    public func send(data: Data) {
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocketTask?.send(message) { error in
            if let error = error {
                print("☁️ Send error: \(error)")
            }
        }
    }
    
    // MARK: - Video Streaming
    
    private var lastFrameTime: Date = .distantPast
    private var frameCount: Int = 0
    
    /// Stream a video frame to the cloud (throttled based on settings)
    public func streamFrame(_ imageData: Data) {
        guard isConnected else { return }
        
        let settings = StreamingSettings.shared
        guard settings.cloudStreamingEnabled else { return }
        
        // Throttle frames based on settings
        let now = Date()
        guard now.timeIntervalSince(lastFrameTime) >= settings.frameInterval else { return }
        lastFrameTime = now
        frameCount += 1
        
        // Create frame message
        let frameMessage: [String: Any] = [
            "type": "video_frame",
            "frame_number": frameCount,
            "timestamp": now.timeIntervalSince1970,
            "quality": settings.streamQuality,
            "size": imageData.count
        ]
        
        // Send metadata first
        if let metaData = try? JSONSerialization.data(withJSONObject: frameMessage) {
            send(data: metaData)
        }
        
        // Send frame data
        send(data: imageData)
        
        if frameCount % 30 == 0 {
            print("☁️ Streamed \(frameCount) frames to cloud")
        }
    }
    
    /// Stream a UIImage frame (convenience method)
    public func streamFrame(_ image: UIImage) {
        let settings = StreamingSettings.shared
        guard let jpegData = image.jpegData(compressionQuality: settings.compressionQuality) else { return }
        streamFrame(jpegData)
    }
    
    /// Send a photo to the cloud server
    public func uploadPhoto(_ data: Data, filename: String) async -> Bool {
        let uploadURL = baseURL.appendingPathComponent("api/upload")
        
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue(filename, forHTTPHeaderField: "X-Filename")
        request.httpBody = data
        
        do {
            let (_, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            print("☁️ Upload failed: \(error)")
            return false
        }
    }
    
    // MARK: - Private
    
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    
    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.reconnectAttempts = 0 // Reset on success
                switch message {
                case .data(let data):
                    self?.handleMessage(data)
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        self?.handleMessage(data)
                    }
                @unknown default:
                    break
                }
                // Continue receiving
                self?.receiveMessages()
                
            case .failure(let error):
                print("☁️ Receive error: \(error)")
                self?.isConnected = false
                self?.webSocketTask = nil
                
                // Auto-reconnect with backoff
                self?.scheduleReconnect()
            }
        }
    }
    
    private func scheduleReconnect() {
        guard StreamingSettings.shared.cloudStreamingEnabled else { return }
        guard reconnectAttempts < maxReconnectAttempts else {
            print("☁️ Max reconnection attempts reached")
            return
        }
        
        reconnectAttempts += 1
        let delay = Double(min(pow(2.0, Double(reconnectAttempts)), 30)) // Max 30 seconds
        
        print("☁️ Reconnecting in \(Int(delay))s (attempt \(reconnectAttempts)/\(maxReconnectAttempts))")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }
    
    private func handleMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }
        
        print("☁️ Received message: \(type)")
        
        switch type {
        case "capture":
            // Cloud requested a photo capture
            NotificationCenter.default.post(name: .cloudRequestedCapture, object: nil)
        case "status":
            // Status update
            break
        default:
            break
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let cloudRequestedCapture = Notification.Name("cloudRequestedCapture")
}
