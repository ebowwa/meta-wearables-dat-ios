/*
 * YOLOModelManager.swift
 * CameraAccess
 *
 * Central manager for discovering, downloading, and loading YOLO models.
 */

import Foundation
import Vision
import CoreML
import Combine

@MainActor
class YOLOModelManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var availableModels: [YOLOModelInfo] = []
    @Published private(set) var downloadStates: [String: YOLOModelDownloadState] = [:]
    @Published private(set) var activeModel: YOLOModelInfo?
    @Published private(set) var loadedVisionModel: VNCoreMLModel?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?
    
    // MARK: - Private Properties
    
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private let modelsDirectoryURL: URL
    private let registryURL: URL?
    
    // MARK: - Initialization
    
    init(cloudRegistryURL: URL? = nil) {
        self.registryURL = cloudRegistryURL
        
        // Create models directory
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.modelsDirectoryURL = documentsURL.appendingPathComponent("YOLOModels", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
        
        // Discover models
        Task {
            await discoverModels()
        }
    }
    
    // MARK: - Model Discovery
    
    func discoverModels() async {
        var models: [YOLOModelInfo] = []
        
        // 1. Discover bundled models
        models.append(contentsOf: discoverBundledModels())
        
        // 2. Discover local downloaded models
        models.append(contentsOf: discoverLocalModels())
        
        // 3. Fetch cloud registry if available
        if let registryURL = registryURL {
            let cloudModels = await fetchCloudRegistry(from: registryURL)
            // Only add cloud models that aren't already local
            for cloudModel in cloudModels {
                if !models.contains(where: { $0.id == cloudModel.id }) {
                    models.append(cloudModel)
                }
            }
        }
        
        self.availableModels = models
        
        // Initialize download states
        for model in models {
            if downloadStates[model.id] == nil {
                downloadStates[model.id] = model.isDownloaded ? .downloaded : .notDownloaded
            }
        }
    }
    
    private func discoverBundledModels() -> [YOLOModelInfo] {
        var bundled: [YOLOModelInfo] = []
        
        // Look for .mlmodelc and .mlpackage in bundle
        let extensions = ["mlmodelc", "mlpackage"]
        for ext in extensions {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                for url in urls {
                    let name = url.deletingPathExtension().lastPathComponent
                    let model = YOLOModelInfo(
                        id: "bundled_\(name)",
                        name: name,
                        description: "Bundled model",
                        source: .bundled(resourceName: name),
                        version: "1.0"
                    )
                    bundled.append(model)
                }
            }
        }
        
        return bundled
    }
    
    private func discoverLocalModels() -> [YOLOModelInfo] {
        var local: [YOLOModelInfo] = []
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            return local
        }
        
        for url in contents where url.pathExtension == "mlmodelc" || url.pathExtension == "mlpackage" {
            let name = url.deletingPathExtension().lastPathComponent
            let model = YOLOModelInfo(
                id: "local_\(name)",
                name: name,
                description: "Downloaded model",
                source: .local(path: url.path),
                version: "1.0"
            )
            local.append(model)
        }
        
        return local
    }
    
    private func fetchCloudRegistry(from url: URL) async -> [YOLOModelInfo] {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let models = try JSONDecoder().decode([YOLOModelInfo].self, from: data)
            return models
        } catch {
            print("Failed to fetch cloud registry: \(error)")
            return []
        }
    }
    
    // MARK: - Model Download
    
    func downloadModel(_ model: YOLOModelInfo) async {
        guard case .remote(let urlString) = model.source,
              let url = URL(string: urlString) else {
            return
        }
        
        downloadStates[model.id] = .downloading(progress: 0)
        
        do {
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            
            // Files from URLSession often lack extensions, but MLModel.compileModel needs them.
            // Create a temporary URL with the correct extension.
            let ext = url.pathExtension
            let tempWithExtURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext.isEmpty ? "mlmodel" : ext)
            
            try FileManager.default.moveItem(at: tempURL, to: tempWithExtURL)
            
            defer {
                try? FileManager.default.removeItem(at: tempWithExtURL)
            }
            
            // Destination URL for the compiled model
            let destURL = modelsDirectoryURL.appendingPathComponent("\(model.id).mlmodelc")
            
            // Compile logic
            if ext == "mlmodel" || ext == "mlpackage" || ext.isEmpty {
                let compiledURL = try await compileModel(at: tempWithExtURL)
                
                // If destination exists, remove it first
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                
                try FileManager.default.moveItem(at: compiledURL, to: destURL)
            } else if ext == "mlmodelc" {
                // Already compiled (unlikely for single file download unless zipped, handling basics)
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.moveItem(at: tempWithExtURL, to: destURL)
            } else {
                throw YOLOModelError.loadFailed(underlying: NSError(domain: "YOLOModelManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported model extension: \(ext)"]))
            }
            
            downloadStates[model.id] = .downloaded
            await discoverModels()
            
        } catch {
            print("Download failed: \(error)")
            downloadStates[model.id] = .failed(error: error.localizedDescription)
        }
    }
    
    func cancelDownload(_ model: YOLOModelInfo) {
        downloadTasks[model.id]?.cancel()
        downloadTasks.removeValue(forKey: model.id)
        downloadStates[model.id] = .notDownloaded
    }
    
    // MARK: - Model Loading
    
    func loadModel(_ model: YOLOModelInfo) async throws {
        guard let localURL = model.localURL else {
            throw YOLOModelError.modelNotFound
        }
        
        isLoading = true
        loadError = nil
        
        do {
            let compiledURL: URL
            
            // Compile if needed
            if localURL.pathExtension == "mlpackage" {
                compiledURL = try await compileModel(at: localURL)
            } else {
                compiledURL = localURL
            }
            
            // Load the model
            let config = MLModelConfiguration()
            config.computeUnits = .all
            
            let mlModel = try MLModel(contentsOf: compiledURL, configuration: config)
            let visionModel = try VNCoreMLModel(for: mlModel)
            
            self.loadedVisionModel = visionModel
            self.activeModel = model
            self.isLoading = false
            
        } catch {
            self.loadError = error.localizedDescription
            self.isLoading = false
            throw error
        }
    }
    
    private func compileModel(at url: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let compiledURL = try MLModel.compileModel(at: url)
                    continuation.resume(returning: compiledURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Model Deletion
    
    func deleteModel(_ model: YOLOModelInfo) {
        // Remove from active model if this is the active one
        if activeModel?.id == model.id {
            activeModel = nil
            loadedVisionModel = nil
        }
        
        // Remove the local file if it exists
        if case .local(let path) = model.source {
            try? FileManager.default.removeItem(atPath: path)
        }
        
        // Also check the YOLOModels directory for any compiled version
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsDir = documentsURL.appendingPathComponent("YOLOModels", isDirectory: true)
        let potentialCompiledPath = modelsDir.appendingPathComponent("\(model.id).mlmodelc")
        if FileManager.default.fileExists(atPath: potentialCompiledPath.path) {
            try? FileManager.default.removeItem(at: potentialCompiledPath)
        }
        
        // Remove from availableModels synchronously (prevents SwiftUI animation conflict)
        availableModels.removeAll { $0.id == model.id }
        
        // Clean up download state
        downloadStates.removeValue(forKey: model.id)
    }
    
    // MARK: - Add Remote Model by URL
    
    func addRemoteModel(name: String, url: URL) {
        // Sanitize URL for GitHub
        var processedURL = url
        if let host = url.host, host.contains("github.com") {
            // Check if it's likely a blob URL (standard browser view)
            if !url.absoluteString.contains("?raw=true") && !url.absoluteString.contains("raw.githubusercontent.com") {
                 if var components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
                    var queryItems = components.queryItems ?? []
                    queryItems.append(URLQueryItem(name: "raw", value: "true"))
                    components.queryItems = queryItems
                    if let newURL = components.url {
                        processedURL = newURL
                    }
                }
            }
        }
        
        // Sanitize name if empty or default
        let finalName = name.isEmpty ? processedURL.lastPathComponent.replacingOccurrences(of: ".mlpackage", with: "").replacingOccurrences(of: ".mlmodelc", with: "") : name

        let model = YOLOModelInfo(
            id: "remote_\(UUID().uuidString.prefix(8))",
            name: finalName,
            description: "Cloud model from \(processedURL.host ?? "unknown")",
            source: .remote(url: processedURL.absoluteString),
            version: "1.0"
        )
        
        availableModels.append(model)
        downloadStates[model.id] = .notDownloaded
    }
}

// MARK: - Errors

enum YOLOModelError: LocalizedError {
    case modelNotFound
    case compilationFailed
    case loadFailed(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Model file not found"
        case .compilationFailed:
            return "Failed to compile model"
        case .loadFailed(let error):
            return "Failed to load model: \(error.localizedDescription)"
        }
    }
}
