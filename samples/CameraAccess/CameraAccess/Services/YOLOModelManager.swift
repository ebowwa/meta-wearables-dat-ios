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
            
            // Move to models directory
            let destURL = modelsDirectoryURL.appendingPathComponent("\(model.id).mlmodelc")
            
            // If it's a .mlpackage, compile it first
            if url.pathExtension == "mlpackage" {
                let compiledURL = try await compileModel(at: tempURL)
                try FileManager.default.moveItem(at: compiledURL, to: destURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: destURL)
            }
            
            downloadStates[model.id] = .downloaded
            await discoverModels()
            
        } catch {
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
        guard case .local(let path) = model.source else { return }
        
        try? FileManager.default.removeItem(atPath: path)
        
        if activeModel?.id == model.id {
            activeModel = nil
            loadedVisionModel = nil
        }
        
        Task {
            await discoverModels()
        }
    }
    
    // MARK: - Add Remote Model by URL
    
    func addRemoteModel(name: String, url: URL) {
        let model = YOLOModelInfo(
            id: "remote_\(UUID().uuidString.prefix(8))",
            name: name,
            description: "Cloud model from \(url.host ?? "unknown")",
            source: .remote(url: url.absoluteString),
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
