import Foundation
import SwiftUI

/// Settings for cloud streaming and server configuration
public final class StreamingSettings: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = StreamingSettings()
    
    // MARK: - UserDefaults Keys
    
    private enum Keys {
        static let cloudStreamingEnabled = "cloudStreamingEnabled"
        static let localServerEnabled = "localServerEnabled"
        static let cloudURL = "cloudURL"
        static let authToken = "authToken"
        static let streamQuality = "streamQuality"
        static let frameRate = "frameRate"
        static let autoConnect = "autoConnect"
        static let uploadPhotosToCloud = "uploadPhotosToCloud"
        static let savePhotosLocally = "savePhotosLocally"
    }
    
    // MARK: - Published Settings
    
    /// Enable/disable streaming to MentraOS Cloud
    @Published public var cloudStreamingEnabled: Bool {
        didSet { UserDefaults.standard.set(cloudStreamingEnabled, forKey: Keys.cloudStreamingEnabled) }
    }
    
    /// Enable/disable local HTTP server (port 8089)
    @Published public var localServerEnabled: Bool {
        didSet { UserDefaults.standard.set(localServerEnabled, forKey: Keys.localServerEnabled) }
    }
    
    /// Cloud server URL
    @Published public var cloudURL: String {
        didSet { UserDefaults.standard.set(cloudURL, forKey: Keys.cloudURL) }
    }
    
    /// JWT auth token for MentraOS cloud authentication
    @Published public var authToken: String {
        didSet { UserDefaults.standard.set(authToken, forKey: Keys.authToken) }
    }
    
    /// JPEG compression quality for streaming (0.1 - 1.0)
    @Published public var streamQuality: Double {
        didSet { UserDefaults.standard.set(streamQuality, forKey: Keys.streamQuality) }
    }
    
    /// Target frame rate for cloud streaming (frames per second)
    @Published public var frameRate: Int {
        didSet { UserDefaults.standard.set(frameRate, forKey: Keys.frameRate) }
    }
    
    /// Auto-connect to cloud on app launch
    @Published public var autoConnect: Bool {
        didSet { UserDefaults.standard.set(autoConnect, forKey: Keys.autoConnect) }
    }
    
    /// Upload captured photos to cloud
    @Published public var uploadPhotosToCloud: Bool {
        didSet { UserDefaults.standard.set(uploadPhotosToCloud, forKey: Keys.uploadPhotosToCloud) }
    }
    
    /// Save photos to local gallery
    @Published public var savePhotosLocally: Bool {
        didSet { UserDefaults.standard.set(savePhotosLocally, forKey: Keys.savePhotosLocally) }
    }
    
    // MARK: - Computed Properties
    
    /// Compression quality as CGFloat for UIImage
    public var compressionQuality: CGFloat {
        CGFloat(streamQuality)
    }
    
    /// Frame interval for throttling (in seconds)
    public var frameInterval: TimeInterval {
        1.0 / Double(frameRate)
    }
    
    /// Parsed cloud URL
    public var cloudBaseURL: URL? {
        URL(string: cloudURL)
    }
    
    // MARK: - Initialization
    
    private init() {
        let defaults = UserDefaults.standard
        
        // Default JWT token for MentraOS cloud (24-hour expiry, regenerate as needed)
        let defaultToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6InRlc3RAbWVudHJhLmdsYXNzIiwic3ViIjoidGVzdC11c2VyIiwiaWF0IjoxNzY2Mjc0Nzk0LCJleHAiOjE3NjYzNjExOTR9.nL1h7AnOXO79gbOHeYLOagWzXySvwbPEgjthFx_Rs6o"
        
        // Load saved settings or use defaults
        self.cloudStreamingEnabled = defaults.object(forKey: Keys.cloudStreamingEnabled) as? Bool ?? true
        self.localServerEnabled = defaults.object(forKey: Keys.localServerEnabled) as? Bool ?? true
        self.cloudURL = defaults.string(forKey: Keys.cloudURL) ?? "https://6bd3f5f5f3f2.ngrok-free.app"
        self.authToken = defaults.string(forKey: Keys.authToken) ?? defaultToken
        self.streamQuality = defaults.object(forKey: Keys.streamQuality) as? Double ?? 0.5
        self.frameRate = defaults.object(forKey: Keys.frameRate) as? Int ?? 10
        self.autoConnect = defaults.object(forKey: Keys.autoConnect) as? Bool ?? true
        self.uploadPhotosToCloud = defaults.object(forKey: Keys.uploadPhotosToCloud) as? Bool ?? true
        self.savePhotosLocally = defaults.object(forKey: Keys.savePhotosLocally) as? Bool ?? true
    }
    
    // MARK: - Presets
    
    /// Low bandwidth preset (mobile data)
    public func applyLowBandwidthPreset() {
        streamQuality = 0.3
        frameRate = 5
    }
    
    /// High quality preset (WiFi)
    public func applyHighQualityPreset() {
        streamQuality = 0.8
        frameRate = 24
    }
    
    /// Balanced preset
    public func applyBalancedPreset() {
        streamQuality = 0.5
        frameRate = 10
    }
    
    /// Reset to defaults
    public func resetToDefaults() {
        cloudStreamingEnabled = false
        localServerEnabled = true
        cloudURL = "https://olive-results-train.loca.lt"
        streamQuality = 0.5
        frameRate = 10
        autoConnect = true
        uploadPhotosToCloud = true
        savePhotosLocally = true
    }
}

// MARK: - Settings View

public struct StreamingSettingsView: View {
    @ObservedObject var settings = StreamingSettings.shared
    @ObservedObject var cloudClient = CloudClient.shared
    @State private var isTestingConnection = false
    @State private var connectionTestResult: String?
    
    public init() {}
    
    public var body: some View {
        Form {
            // Cloud Connection Section
            Section {
                Toggle("Cloud Streaming", isOn: $settings.cloudStreamingEnabled)
                
                if settings.cloudStreamingEnabled {
                    TextField("Cloud URL", text: $settings.cloudURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    
                    Toggle("Auto-connect on Launch", isOn: $settings.autoConnect)
                    
                    HStack {
                        Button(action: testConnection) {
                            HStack {
                                if isTestingConnection {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: cloudClient.isConnected ? "checkmark.circle.fill" : "wifi")
                                }
                                Text(cloudClient.isConnected ? "Connected" : "Test Connection")
                            }
                        }
                        .disabled(isTestingConnection)
                        
                        if let result = connectionTestResult {
                            Text(result)
                                .font(.caption)
                                .foregroundColor(result.contains("✅") ? .green : .red)
                        }
                    }
                }
            } header: {
                Text("☁️ Cloud Server")
            } footer: {
                Text("Stream video to your MentraOS cloud server for remote access and AI processing.")
            }
            
            // Local Server Section
            Section {
                Toggle("Local HTTP Server", isOn: $settings.localServerEnabled)
                
                if settings.localServerEnabled, let url = ASGServerManager.shared.serverURL {
                    HStack {
                        Text("URL")
                        Spacer()
                        Text(url)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("📡 Local Server")
            } footer: {
                Text("Access camera from devices on your local network via port 8089.")
            }
            
            // Quality Settings Section
            Section {
                VStack(alignment: .leading) {
                    Text("Stream Quality: \(Int(settings.streamQuality * 100))%")
                    Slider(value: $settings.streamQuality, in: 0.1...1.0, step: 0.1)
                }
                
                Stepper("Frame Rate: \(settings.frameRate) fps", value: $settings.frameRate, in: 1...30)
                
                HStack {
                    Button("Low") { settings.applyLowBandwidthPreset() }
                        .buttonStyle(.bordered)
                    Button("Balanced") { settings.applyBalancedPreset() }
                        .buttonStyle(.bordered)
                    Button("High") { settings.applyHighQualityPreset() }
                        .buttonStyle(.bordered)
                }
            } header: {
                Text("⚡ Quality")
            }
            
            // Photo Settings Section
            Section {
                Toggle("Upload Photos to Cloud", isOn: $settings.uploadPhotosToCloud)
                Toggle("Save Photos Locally", isOn: $settings.savePhotosLocally)
            } header: {
                Text("📷 Photos")
            }
            
            // Reset Section
            Section {
                Button("Reset to Defaults", role: .destructive) {
                    settings.resetToDefaults()
                }
            }
        }
        .navigationTitle("Streaming Settings")
    }
    
    private func testConnection() {
        isTestingConnection = true
        connectionTestResult = nil
        
        Task {
            let healthy = await CloudClient.shared.checkHealth()
            await MainActor.run {
                isTestingConnection = false
                connectionTestResult = healthy ? "✅ OK" : "❌ Failed"
                
                if healthy && !cloudClient.isConnected {
                    CloudClient.shared.connect()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        StreamingSettingsView()
    }
}
