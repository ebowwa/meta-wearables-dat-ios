# 📸 ASG Camera Server for iOS

A Swift port of the MentraOS Android camera server, designed for Meta glasses iOS apps.

## 🚀 Features

### ✨ Core Functionality

- **📱 Modern Web Interface**: Beautiful, responsive dark-mode UI optimized for mobile devices
- **🖼️ Photo Gallery**: Browse all captured photos with metadata
- **⬇️ Direct Download**: Download photos directly to any device
- **📸 Remote Capture**: Trigger photo capture from any device on the network
- **🔄 Real-time Updates**: Auto-refresh gallery every 10 seconds
- **🔒 Security**: Rate limiting, CORS support, and input validation
- **⚡ Performance**: LRU file caching and optimized delivery

### 🌐 API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Main web interface |
| `/api/take-picture` | POST | Trigger photo capture |
| `/api/start-recording` | POST | Start video recording |
| `/api/stop-recording` | POST | Stop video recording |
| `/api/latest-photo` | GET | Get the most recent photo |
| `/api/gallery` | GET | List all photos with metadata |
| `/api/photo?file=filename` | GET | Get a specific photo |
| `/api/download?file=filename` | GET | Download a photo |
| `/api/status` | GET | Server status information |
| `/api/health` | GET | Health check endpoint |
| `/api/cleanup` | GET | Clean up old files |

## 🔧 Usage

### Quick Start

```swift
import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Start the camera server
        ASGServerManager.shared.startServer(delegate: self)
        
        return true
    }
}

extension AppDelegate: ASGCameraServerDelegate {
    func cameraServerDidRequestCapture(_ server: ASGCameraServer) {
        // Trigger photo capture on Meta glasses
        print("📸 Capture requested!")
    }
    
    func cameraServerDidRequestStartRecording(_ server: ASGCameraServer) {
        // Start video recording
        print("🎥 Start recording!")
    }
    
    func cameraServerDidRequestStopRecording(_ server: ASGCameraServer) {
        // Stop video recording
        print("🛑 Stop recording!")
    }
}
```

### SwiftUI Integration

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        CameraView()
            .withASGServer(delegate: cameraDelegate, autoStart: true)
    }
}
```

### Custom Configuration

```swift
let config = ServerConfig(
    port: 8089,
    serverName: "Meta Glasses Camera",
    corsEnabled: true,
    maxFileSize: 50 * 1024 * 1024,  // 50MB
    maxRequestsPerWindow: 100,
    rateLimitWindowSeconds: 60
)

ASGServerManager.shared.configure(with: config)
ASGServerManager.shared.startServer(delegate: self)
```

### Saving Photos

```swift
// Save a photo from Data
if let url = ASGServerManager.shared.savePhoto(imageData, named: "captured.jpg") {
    print("Photo saved to: \(url)")
}

// Save a video from URL
if let url = ASGServerManager.shared.saveVideo(from: videoURL, named: "recording.mp4") {
    print("Video saved to: \(url)")
}

// Update latest photo for live preview
ASGServerManager.shared.updateLatestPhoto(frameData)
```

## 📱 Architecture

```
┌──────────────────┐    DAT SDK    ┌───────────────────────┐    HTTP/WiFi    ┌─────────────────┐
│  Meta Ray-Bans   │ ────────────► │   iPhone (iOS App)    │ ◄─────────────► │  Other Devices  │
│    (glasses)     │   Bluetooth   │  - DAT SDK receiver   │                 │  (browser/app)  │
└──────────────────┘               │  - ASG Camera Server  │                 └─────────────────┘
                                   │  - Gallery API        │
                                   └───────────────────────┘
```

## 📂 File Structure

```
Server/
├── Core/
│   ├── ServerConfig.swift      # Server configuration
│   ├── NetworkProvider.swift   # IP address detection
│   ├── RateLimiter.swift       # Request rate limiting
│   ├── CacheManager.swift      # LRU file cache
│   └── ASGServer.swift         # Base HTTP server
├── Services/
│   └── ASGCameraServer.swift   # Camera-specific endpoints
├── Managers/
│   └── ASGServerManager.swift  # Singleton manager
└── README.md
```

## 🔒 Security Features

- **Rate Limiting**: 100 requests per minute per IP (configurable)
- **Input Validation**: Prevents directory traversal attacks
- **File Size Limits**: 50MB maximum file size
- **CORS Support**: Cross-origin requests for web apps

## 🔧 Requirements

- iOS 14.0+
- Swift 5.5+
- Network framework (built-in)

## 📝 Notes

This is a Swift port of the MentraOS Android `asg_client` camera server. Key differences:

- Uses `NWListener` instead of NanoHTTPD
- Native Swift code instead of Java
- iOS-specific file handling
- SwiftUI integration support

---

**Need Help?** Check the logs for detailed error messages or file an issue.
