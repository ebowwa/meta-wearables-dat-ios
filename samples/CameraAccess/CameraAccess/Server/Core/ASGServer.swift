import Foundation
import Network

/// HTTP Request representation
public struct HTTPRequest {
    public let method: String
    public let uri: String
    public let headers: [String: String]
    public let queryParams: [String: String]
    public let body: Data?
    public let clientIP: String
    
    public init(method: String, uri: String, headers: [String: String], queryParams: [String: String], body: Data?, clientIP: String) {
        self.method = method
        self.uri = uri
        self.headers = headers
        self.queryParams = queryParams
        self.body = body
        self.clientIP = clientIP
    }
}

/// HTTP Response representation
public struct HTTPResponse {
    public let statusCode: Int
    public let statusMessage: String
    public let headers: [String: String]
    public let body: Data?
    
    public init(statusCode: Int, statusMessage: String, headers: [String: String] = [:], body: Data? = nil) {
        self.statusCode = statusCode
        self.statusMessage = statusMessage
        self.headers = headers
        self.body = body
    }
    
    // Common status responses
    public static func ok(body: Data?, contentType: String = "application/json") -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            statusMessage: "OK",
            headers: ["Content-Type": contentType],
            body: body
        )
    }
    
    public static func notFound(_ message: String = "Not Found") -> HTTPResponse {
        let body = "{\"status\":\"error\",\"message\":\"\(message)\"}".data(using: .utf8)
        return HTTPResponse(statusCode: 404, statusMessage: "Not Found", headers: ["Content-Type": "application/json"], body: body)
    }
    
    public static func badRequest(_ message: String = "Bad Request") -> HTTPResponse {
        let body = "{\"status\":\"error\",\"message\":\"\(message)\"}".data(using: .utf8)
        return HTTPResponse(statusCode: 400, statusMessage: "Bad Request", headers: ["Content-Type": "application/json"], body: body)
    }
    
    public static func internalError(_ message: String = "Internal Server Error") -> HTTPResponse {
        let body = "{\"status\":\"error\",\"message\":\"\(message)\"}".data(using: .utf8)
        return HTTPResponse(statusCode: 500, statusMessage: "Internal Server Error", headers: ["Content-Type": "application/json"], body: body)
    }
    
    public static func tooManyRequests(_ message: String = "Rate limit exceeded") -> HTTPResponse {
        let body = "{\"status\":\"error\",\"message\":\"\(message)\"}".data(using: .utf8)
        return HTTPResponse(statusCode: 429, statusMessage: "Too Many Requests", headers: ["Content-Type": "application/json"], body: body)
    }
    
    public static func json(_ dictionary: [String: Any]) -> HTTPResponse {
        do {
            let data = try JSONSerialization.data(withJSONObject: dictionary, options: [])
            return HTTPResponse.ok(body: data, contentType: "application/json")
        } catch {
            return HTTPResponse.internalError("Failed to serialize JSON")
        }
    }
    
    public static func success(_ data: [String: Any]) -> HTTPResponse {
        var response: [String: Any] = ["status": "success"]
        response["data"] = data
        return json(response)
    }
}

/// Abstract base class for ASG HTTP servers
/// Uses NWListener for the underlying networking
open class ASGServer {
    
    // MARK: - Properties
    
    public let config: ServerConfig
    public let networkProvider: NetworkProviding
    public let cacheManager: CacheManaging
    public let rateLimiter: RateLimiting
    
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.asg.server", qos: .userInitiated)
    private var connections: [NWConnection] = []
    private let connectionsLock = NSLock()
    
    public private(set) var isRunning = false
    
    // MARK: - Initialization
    
    public init(
        config: ServerConfig = .default,
        networkProvider: NetworkProviding = NetworkProvider(),
        cacheManager: CacheManaging = CacheManager(),
        rateLimiter: RateLimiting = RateLimiter()
    ) {
        self.config = config
        self.networkProvider = networkProvider
        self.cacheManager = cacheManager
        self.rateLimiter = rateLimiter
        
        print("🚀 =========================================")
        print("🚀 \(config.serverName) INITIALIZED")
        print("🚀 =========================================")
        print("🚀 📍 Port: \(config.port)")
        print("🚀 📍 Max file size: \(config.maxFileSize) bytes")
        print("🚀 📍 Rate limit: \(config.maxRequestsPerWindow) requests per \(config.rateLimitWindowSeconds)s")
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Server Control
    
    /// Start the HTTP server
    public func start() throws {
        guard !isRunning else {
            print("⚠️ Server already running")
            return
        }
        
        print("🚀 =========================================")
        print("🚀 STARTING \(config.serverName)")
        print("🚀 =========================================")
        
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: config.port)!)
        } catch {
            print("❌ Failed to create listener: \(error)")
            throw error
        }
        
        listener?.stateUpdateHandler = { [weak self] state in
            self?.handleListenerState(state)
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        listener?.start(queue: queue)
        isRunning = true
        
        print("✅ \(config.serverName) started on port \(config.port)")
        
        if let ip = networkProvider.getBestIPAddress() {
            print("🌐 Server URL: http://\(ip):\(config.port)")
        }
    }
    
    /// Stop the HTTP server
    public func stop() {
        guard isRunning else { return }
        
        print("🛑 =========================================")
        print("🛑 STOPPING \(config.serverName)")
        print("🛑 =========================================")
        
        listener?.cancel()
        listener = nil
        
        connectionsLock.lock()
        connections.forEach { $0.cancel() }
        connections.removeAll()
        connectionsLock.unlock()
        
        cacheManager.clear()
        isRunning = false
        
        print("🛑 ✅ \(config.serverName) stopped")
    }
    
    /// Get the server URL
    public var serverURL: String? {
        guard let ip = networkProvider.getBestIPAddress() else { return nil }
        return "http://\(ip):\(config.port)"
    }
    
    // MARK: - Connection Handling
    
    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            print("✅ Server ready and listening")
        case .failed(let error):
            print("❌ Server failed: \(error)")
            isRunning = false
        case .cancelled:
            print("🛑 Server cancelled")
            isRunning = false
        default:
            break
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connectionsLock.lock()
        connections.append(connection)
        connectionsLock.unlock()
        
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .ready:
                self?.receiveData(on: connection!)
            case .failed, .cancelled:
                self?.removeConnection(connection)
            default:
                break
            }
        }
        
        connection.start(queue: queue)
    }
    
    private func removeConnection(_ connection: NWConnection?) {
        guard let connection = connection else { return }
        
        connectionsLock.lock()
        connections.removeAll { $0 === connection }
        connectionsLock.unlock()
    }
    
    private func receiveData(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Receive error: \(error)")
                connection.cancel()
                return
            }
            
            if let data = data, !data.isEmpty {
                self.handleHTTPData(data, on: connection)
            }
            
            if isComplete {
                connection.cancel()
            } else {
                self.receiveData(on: connection)
            }
        }
    }
    
    private func handleHTTPData(_ data: Data, on connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendResponse(.badRequest("Invalid request encoding"), on: connection)
            return
        }
        
        // Parse HTTP request
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(.badRequest("Empty request"), on: connection)
            return
        }
        
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(.badRequest("Invalid request line"), on: connection)
            return
        }
        
        let method = String(parts[0])
        let fullPath = String(parts[1])
        
        // Parse URI and query params
        var uri = fullPath
        var queryParams: [String: String] = [:]
        
        if let queryIndex = fullPath.firstIndex(of: "?") {
            uri = String(fullPath[..<queryIndex])
            let queryString = String(fullPath[fullPath.index(after: queryIndex)...])
            queryParams = parseQueryString(queryString)
        }
        
        // Parse headers
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        
        // Get client IP
        let clientIP = connection.endpoint.debugDescription
        
        // Check rate limiting
        if !rateLimiter.isAllowed(ip: clientIP) {
            print("🚫 Rate limit exceeded for IP: \(clientIP)")
            sendResponse(.tooManyRequests(), on: connection)
            return
        }
        rateLimiter.recordRequest(ip: clientIP)
        
        // Create request object
        let request = HTTPRequest(
            method: method,
            uri: uri,
            headers: headers,
            queryParams: queryParams,
            body: nil, // TODO: Parse body for POST requests
            clientIP: clientIP
        )
        
        print("🔍 \(method) \(uri) from \(clientIP)")
        
        // Handle CORS preflight
        if method == "OPTIONS" {
            var response = HTTPResponse.ok(body: nil)
            if config.corsEnabled {
                response = HTTPResponse(
                    statusCode: 200,
                    statusMessage: "OK",
                    headers: corsHeaders(),
                    body: nil
                )
            }
            sendResponse(response, on: connection)
            return
        }
        
        // Route to handler
        let response = handleRequest(request)
        sendResponse(response, on: connection)
    }
    
    private func parseQueryString(_ query: String) -> [String: String] {
        var params: [String: String] = [:]
        let pairs = query.split(separator: "&")
        for pair in pairs {
            let keyValue = pair.split(separator: "=", maxSplits: 1)
            if keyValue.count == 2 {
                let key = String(keyValue[0]).removingPercentEncoding ?? String(keyValue[0])
                let value = String(keyValue[1]).removingPercentEncoding ?? String(keyValue[1])
                params[key] = value
            }
        }
        return params
    }
    
    private func corsHeaders() -> [String: String] {
        return [
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type"
        ]
    }
    
    private func sendResponse(_ response: HTTPResponse, on connection: NWConnection) {
        var responseString = "HTTP/1.1 \(response.statusCode) \(response.statusMessage)\r\n"
        
        var headers = response.headers
        if config.corsEnabled {
            corsHeaders().forEach { headers[$0.key] = $0.value }
        }
        
        if let body = response.body {
            headers["Content-Length"] = "\(body.count)"
        }
        
        for (key, value) in headers {
            responseString += "\(key): \(value)\r\n"
        }
        
        responseString += "\r\n"
        
        var responseData = responseString.data(using: .utf8)!
        if let body = response.body {
            responseData.append(body)
        }
        
        connection.send(content: responseData, completion: .contentProcessed { error in
            if let error = error {
                print("❌ Send error: \(error)")
            }
            connection.cancel()
        })
    }
    
    // MARK: - Request Handling (Override in subclass)
    
    /// Handle an HTTP request - override in subclass
    open func handleRequest(_ request: HTTPRequest) -> HTTPResponse {
        return .notFound("No handler implemented")
    }
    
    // MARK: - Utility Methods
    
    /// Get MIME type for file extension
    public func mimeType(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "css": return "text/css"
        case "js": return "application/javascript"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "html", "htm": return "text/html"
        case "json": return "application/json"
        case "xml": return "application/xml"
        case "txt": return "text/plain"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        default: return "application/octet-stream"
        }
    }
}
