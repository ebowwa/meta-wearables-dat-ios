import Foundation
import UIKit

/// Photo metadata for gallery responses
public struct PhotoMetadata: Codable {
    public let name: String
    public let size: Int64
    public let modified: String
    public let mimeType: String
    public let url: String
    public let downloadURL: String
    public let isVideo: Bool
    public let thumbnailURL: String?
    
    public init(name: String, size: Int64, modified: Date, mimeType: String, baseURL: String, isVideo: Bool = false) {
        self.name = name
        self.size = size
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        self.modified = formatter.string(from: modified)
        
        self.mimeType = mimeType
        self.url = "/api/photo?file=\(name)"
        self.downloadURL = "/api/download?file=\(name)"
        self.isVideo = isVideo
        self.thumbnailURL = isVideo ? "/api/photo?file=\(name)" : nil
    }
}

/// Delegate protocol for camera server events
public protocol ASGCameraServerDelegate: AnyObject {
    /// Called when a take-picture request is received
    func cameraServerDidRequestCapture(_ server: ASGCameraServer)
    
    /// Called when a start-recording request is received
    func cameraServerDidRequestStartRecording(_ server: ASGCameraServer)
    
    /// Called when a stop-recording request is received
    func cameraServerDidRequestStopRecording(_ server: ASGCameraServer)
}

/// Camera web server for Meta glasses iOS app
/// Provides RESTful API for photo capture, gallery browsing, and file downloads
public final class ASGCameraServer: ASGServer {
    
    // MARK: - Properties
    
    /// Delegate for handling camera events
    public weak var delegate: ASGCameraServerDelegate?
    
    /// Directory where photos are stored
    public var photosDirectory: URL
    
    /// Latest captured photo data (for quick access)
    private var latestPhotoData: Data?
    private var latestPhotoName: String?
    
    /// Server start time for uptime calculation
    private let startTime = Date()
    
    // MARK: - Initialization
    
    public init(
        config: ServerConfig = .default,
        photosDirectory: URL? = nil
    ) {
        // Default to Documents/Photos directory
        let defaultDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Photos", isDirectory: true)
        
        self.photosDirectory = photosDirectory ?? defaultDir
        
        super.init(config: config)
        
        // Ensure photos directory exists
        try? FileManager.default.createDirectory(at: self.photosDirectory, withIntermediateDirectories: true)
        
        print("📸 Camera server initialized")
        print("📸 Photos directory: \(self.photosDirectory.path)")
    }
    
    // MARK: - Request Handling
    
    public override func handleRequest(_ request: HTTPRequest) -> HTTPResponse {
        switch request.uri {
        case "/":
            return serveIndexPage()
        case "/api/take-picture":
            return handleTakePicture()
        case "/api/start-recording":
            return handleStartRecording()
        case "/api/stop-recording":
            return handleStopRecording()
        case "/api/latest-photo":
            return serveLatestPhoto()
        case "/api/gallery":
            return serveGallery(request: request)
        case "/api/photo":
            return servePhoto(request: request)
        case "/api/download":
            return serveDownload(request: request)
        case "/api/status":
            return serveStatus()
        case "/api/health":
            return serveHealth()
        case "/api/cleanup":
            return serveCleanup(request: request)
        default:
            if request.uri.hasPrefix("/static/") {
                return serveStaticFile(request: request)
            }
            return .notFound("Endpoint not found: \(request.uri)")
        }
    }
    
    // MARK: - Endpoint Handlers
    
    private func serveIndexPage() -> HTTPResponse {
        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Meta Glasses Camera</title>
            <style>
                * { box-sizing: border-box; margin: 0; padding: 0; }
                body { 
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
                    color: #fff; min-height: 100vh; padding: 20px;
                }
                .container { max-width: 1200px; margin: 0 auto; }
                h1 { text-align: center; margin-bottom: 30px; font-size: 2em; }
                .status-bar { 
                    background: rgba(255,255,255,0.1); padding: 15px; 
                    border-radius: 12px; margin-bottom: 20px;
                    display: flex; justify-content: space-between; align-items: center;
                }
                .status-dot { width: 12px; height: 12px; border-radius: 50%; 
                    background: #4ade80; animation: pulse 2s infinite; }
                @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }
                .controls { display: flex; gap: 15px; margin-bottom: 30px; flex-wrap: wrap; }
                .btn {
                    flex: 1; min-width: 150px; padding: 15px 25px; border: none;
                    border-radius: 12px; font-size: 16px; font-weight: 600;
                    cursor: pointer; transition: all 0.3s;
                }
                .btn-primary { background: #3b82f6; color: white; }
                .btn-primary:hover { background: #2563eb; transform: translateY(-2px); }
                .btn-secondary { background: rgba(255,255,255,0.15); color: white; }
                .btn-secondary:hover { background: rgba(255,255,255,0.25); }
                .gallery { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 15px; }
                .photo-card {
                    background: rgba(255,255,255,0.1); border-radius: 12px; overflow: hidden;
                    transition: transform 0.3s;
                }
                .photo-card:hover { transform: scale(1.02); }
                .photo-card img { width: 100%; height: 180px; object-fit: cover; }
                .photo-info { padding: 12px; }
                .photo-name { font-weight: 500; margin-bottom: 5px; word-break: break-all; }
                .photo-meta { font-size: 12px; color: rgba(255,255,255,0.6); }
                .photo-actions { display: flex; gap: 8px; margin-top: 10px; }
                .photo-actions .btn { padding: 8px 12px; font-size: 12px; }
                .loading { text-align: center; padding: 40px; color: rgba(255,255,255,0.6); }
                .empty { text-align: center; padding: 60px; }
                .empty-icon { font-size: 48px; margin-bottom: 15px; }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>📸 Meta Glasses Camera</h1>
                
                <div class="status-bar">
                    <div style="display: flex; align-items: center; gap: 10px;">
                        <div class="status-dot"></div>
                        <span id="status">Connected</span>
                    </div>
                    <span id="photo-count">0 photos</span>
                </div>
                
                <div class="controls">
                    <button class="btn btn-primary" onclick="takePicture()">📷 Take Photo</button>
                    <button class="btn btn-secondary" onclick="refreshGallery()">🔄 Refresh</button>
                </div>
                
                <div id="gallery" class="gallery">
                    <div class="loading">Loading photos...</div>
                </div>
            </div>
            
            <script>
                async function takePicture() {
                    try {
                        const res = await fetch('/api/take-picture', { method: 'POST' });
                        const data = await res.json();
                        if (data.status === 'success') {
                            setTimeout(refreshGallery, 1000);
                        }
                    } catch (e) { console.error('Take picture failed:', e); }
                }
                
                async function refreshGallery() {
                    try {
                        const res = await fetch('/api/gallery');
                        const data = await res.json();
                        
                        if (data.status !== 'success') {
                            document.getElementById('gallery').innerHTML = '<div class="loading">Error loading gallery</div>';
                            return;
                        }
                        
                        const photos = data.data.photos || [];
                        document.getElementById('photo-count').textContent = photos.length + ' photos';
                        
                        if (photos.length === 0) {
                            document.getElementById('gallery').innerHTML = 
                                '<div class="empty"><div class="empty-icon">📷</div><p>No photos yet. Take your first photo!</p></div>';
                            return;
                        }
                        
                        document.getElementById('gallery').innerHTML = photos.map(p => `
                            <div class="photo-card">
                                <img src="${p.url}" alt="${p.name}" loading="lazy" onerror="this.src='data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><rect fill=%22%23333%22 width=%22100%22 height=%22100%22/><text x=%2250%22 y=%2255%22 text-anchor=%22middle%22 fill=%22%23666%22 font-size=%2220%22>📷</text></svg>'">
                                <div class="photo-info">
                                    <div class="photo-name">${p.name}</div>
                                    <div class="photo-meta">${formatSize(p.size)} • ${p.modified}</div>
                                    <div class="photo-actions">
                                        <a class="btn btn-secondary" href="${p.download}" download>⬇️ Download</a>
                                    </div>
                                </div>
                            </div>
                        `).join('');
                    } catch (e) {
                        console.error('Gallery refresh failed:', e);
                        document.getElementById('gallery').innerHTML = '<div class="loading">Error loading gallery</div>';
                    }
                }
                
                function formatSize(bytes) {
                    if (bytes < 1024) return bytes + ' B';
                    if (bytes < 1024*1024) return (bytes/1024).toFixed(1) + ' KB';
                    return (bytes/(1024*1024)).toFixed(1) + ' MB';
                }
                
                refreshGallery();
                setInterval(refreshGallery, 10000);
            </script>
        </body>
        </html>
        """
        return HTTPResponse.ok(body: html.data(using: .utf8), contentType: "text/html")
    }
    
    private func handleTakePicture() -> HTTPResponse {
        print("📸 Take picture request received")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.cameraServerDidRequestCapture(self)
        }
        
        return .success([
            "message": "Picture request received",
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ])
    }
    
    private func handleStartRecording() -> HTTPResponse {
        print("🎥 Start recording request received")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.cameraServerDidRequestStartRecording(self)
        }
        
        return .success([
            "message": "Start recording request received",
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ])
    }
    
    private func handleStopRecording() -> HTTPResponse {
        print("🛑 Stop recording request received")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.cameraServerDidRequestStopRecording(self)
        }
        
        return .success([
            "message": "Stop recording request received",
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ])
    }
    
    private func serveLatestPhoto() -> HTTPResponse {
        // Try cached latest photo first
        if let data = latestPhotoData {
            return HTTPResponse.ok(body: data, contentType: "image/jpeg")
        }
        
        // Otherwise find the most recent photo
        guard let latestFile = getLatestPhoto() else {
            return .notFound("No photo taken yet")
        }
        
        do {
            let data = try Data(contentsOf: latestFile.url)
            return HTTPResponse.ok(body: data, contentType: mimeType(for: latestFile.name))
        } catch {
            return .internalError("Error reading photo file")
        }
    }
    
    private func serveGallery(request: HTTPRequest) -> HTTPResponse {
        let limit = Int(request.queryParams["limit"] ?? "") ?? 0
        let offset = Int(request.queryParams["offset"] ?? "") ?? 0
        
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: photosDirectory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .contentTypeKey],
                options: [.skipsHiddenFiles]
            )
            
            // Filter to media files and get metadata
            var photoMetadata: [(url: URL, name: String, size: Int64, modified: Date)] = []
            
            for file in files {
                let ext = file.pathExtension.lowercased()
                guard ["jpg", "jpeg", "png", "gif", "mp4", "mov", "heic"].contains(ext) else { continue }
                
                let resources = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                photoMetadata.append((
                    url: file,
                    name: file.lastPathComponent,
                    size: Int64(resources.fileSize ?? 0),
                    modified: resources.contentModificationDate ?? Date()
                ))
            }
            
            // Sort by modification date (newest first)
            photoMetadata.sort { $0.modified > $1.modified }
            
            let totalCount = photoMetadata.count
            let totalSize = photoMetadata.reduce(0) { $0 + $1.size }
            
            // Apply pagination
            let startIndex = min(offset, totalCount)
            let endIndex = limit > 0 ? min(startIndex + limit, totalCount) : totalCount
            let paginatedItems = Array(photoMetadata[startIndex..<endIndex])
            
            // Build response
            let photos: [[String: Any]] = paginatedItems.map { item in
                let isVideo = ["mp4", "mov"].contains(item.url.pathExtension.lowercased())
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                
                var photo: [String: Any] = [
                    "name": item.name,
                    "size": item.size,
                    "modified": formatter.string(from: item.modified),
                    "mime_type": mimeType(for: item.name),
                    "url": "/api/photo?file=\(item.name)",
                    "download": "/api/download?file=\(item.name)",
                    "is_video": isVideo
                ]
                
                if isVideo {
                    photo["thumbnail_url"] = "/api/photo?file=\(item.name)"
                }
                
                return photo
            }
            
            return .success([
                "photos": photos,
                "total_count": totalCount,
                "returned_count": photos.count,
                "total_size": totalSize,
                "offset": offset,
                "limit": limit,
                "has_more": endIndex < totalCount
            ])
            
        } catch {
            print("❌ Error reading gallery: \(error)")
            return .internalError("Error reading gallery")
        }
    }
    
    private func servePhoto(request: HTTPRequest) -> HTTPResponse {
        guard let filename = request.queryParams["file"], !filename.isEmpty else {
            return .badRequest("File parameter required")
        }
        
        // Security: prevent directory traversal
        guard !filename.contains("..") && !filename.contains("/") else {
            return .badRequest("Invalid file path")
        }
        
        let fileURL = photosDirectory.appendingPathComponent(filename)
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .notFound("Photo not found")
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            return HTTPResponse.ok(body: data, contentType: mimeType(for: filename))
        } catch {
            return .internalError("Error reading photo file")
        }
    }
    
    private func serveDownload(request: HTTPRequest) -> HTTPResponse {
        guard let filename = request.queryParams["file"], !filename.isEmpty else {
            return .badRequest("File parameter required")
        }
        
        // Security: prevent directory traversal
        guard !filename.contains("..") && !filename.contains("/") else {
            return .badRequest("Invalid file path")
        }
        
        let fileURL = photosDirectory.appendingPathComponent(filename)
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .notFound("Photo not found")
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            return HTTPResponse(
                statusCode: 200,
                statusMessage: "OK",
                headers: [
                    "Content-Type": mimeType(for: filename),
                    "Content-Disposition": "attachment; filename=\"\(filename)\"",
                    "Content-Length": "\(data.count)"
                ],
                body: data
            )
        } catch {
            return .internalError("Error downloading photo file")
        }
    }
    
    private func serveStatus() -> HTTPResponse {
        let uptime = Date().timeIntervalSince(startTime)
        
        // Count photos
        let photoCount = (try? FileManager.default.contentsOfDirectory(atPath: photosDirectory.path).count) ?? 0
        
        return .success([
            "server_name": config.serverName,
            "port": Int(config.port),
            "uptime_seconds": Int(uptime),
            "photo_count": photoCount,
            "photos_directory": photosDirectory.path,
            "server_url": serverURL ?? "unknown",
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ])
    }
    
    private func serveHealth() -> HTTPResponse {
        return .success([
            "status": "healthy",
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ])
    }
    
    private func serveCleanup(request: HTTPRequest) -> HTTPResponse {
        let maxAgeHours = Int(request.queryParams["max_age_hours"] ?? "") ?? 24
        let maxAgeSeconds = TimeInterval(maxAgeHours * 3600)
        let cutoffDate = Date().addingTimeInterval(-maxAgeSeconds)
        
        var removedCount = 0
        
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: photosDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            for file in files {
                let resources = try file.resourceValues(forKeys: [.contentModificationDateKey])
                if let modified = resources.contentModificationDate, modified < cutoffDate {
                    try FileManager.default.removeItem(at: file)
                    removedCount += 1
                }
            }
            
            return .success([
                "message": "Cleanup completed successfully",
                "files_removed": removedCount,
                "max_age_hours": maxAgeHours
            ])
            
        } catch {
            return .internalError("Error during cleanup: \(error.localizedDescription)")
        }
    }
    
    private func serveStaticFile(request: HTTPRequest) -> HTTPResponse {
        // Static files would be bundled with the app
        // For now, return not found
        return .notFound("Static file not found")
    }
    
    // MARK: - Public Methods
    
    /// Save a photo to the gallery
    public func savePhoto(_ data: Data, named: String? = nil) -> URL? {
        let filename = named ?? "photo_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        let fileURL = photosDirectory.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL)
            latestPhotoData = data
            latestPhotoName = filename
            print("📸 Saved photo: \(filename)")
            return fileURL
        } catch {
            print("❌ Error saving photo: \(error)")
            return nil
        }
    }
    
    /// Save a video to the gallery
    public func saveVideo(from sourceURL: URL, named: String? = nil) -> URL? {
        let filename = named ?? "video_\(Int(Date().timeIntervalSince1970 * 1000)).mp4"
        let destURL = photosDirectory.appendingPathComponent(filename)
        
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            print("🎥 Saved video: \(filename)")
            return destURL
        } catch {
            print("❌ Error saving video: \(error)")
            return nil
        }
    }
    
    /// Update the latest photo (for live preview)
    public func updateLatestPhoto(_ data: Data) {
        latestPhotoData = data
    }
    
    // MARK: - Private Helpers
    
    private func getLatestPhoto() -> (url: URL, name: String)? {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: photosDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            let sorted = files.compactMap { url -> (url: URL, date: Date)? in
                guard let resources = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                      let date = resources.contentModificationDate else { return nil }
                return (url, date)
            }.sorted { $0.date > $1.date }
            
            if let latest = sorted.first {
                return (latest.url, latest.url.lastPathComponent)
            }
        } catch {
            print("❌ Error finding latest photo: \(error)")
        }
        
        return nil
    }
}
