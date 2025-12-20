import Foundation

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
    
    public let config: CloudConfig
    
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var lastError: String?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession.shared
    
    // MARK: - Singleton
    
    public static let shared = CloudClient()
    
    // MARK: - Initialization
    
    public init(config: CloudConfig = .default) {
        self.config = config
    }
    
    // MARK: - Health Check
    
    /// Check if the cloud server is reachable
    public func checkHealth() async -> Bool {
        do {
            let (data, response) = try await session.data(from: config.healthURL)
            
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
        
        print("☁️ Connecting to cloud: \(config.webSocketURL)")
        
        webSocketTask = session.webSocketTask(with: config.webSocketURL)
        webSocketTask?.resume()
        
        receiveMessages()
        
        // Send initial connection message
        let connectMessage: [String: Any] = [
            "type": "connect",
            "client": "meta-glasses-ios",
            "timestamp": Date().timeIntervalSince1970
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
    
    /// Send a photo to the cloud server
    public func uploadPhoto(_ data: Data, filename: String) async -> Bool {
        let uploadURL = config.baseURL.appendingPathComponent("api/upload")
        
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
    
    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
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
            }
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
