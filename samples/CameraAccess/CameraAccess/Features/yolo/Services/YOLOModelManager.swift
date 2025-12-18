/*
 * YOLOModelManager.swift
 * CameraAccess
 *
 * Central manager for discovering, downloading, and loading YOLO models.
 * Now database-first: reads from SwiftData, discovers new models from filesystem.
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
    @Published private(set) var modelSpec: MLModelSpec = .empty
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: String?
    
    // MARK: - Private Properties
    
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private let modelsDirectoryURL: URL
    private let registryURL: URL?
    private let persistence = YOLOPersistenceManager.shared
    
    // MARK: - Initialization
    
    init(cloudRegistryURL: URL? = nil) {
        self.registryURL = cloudRegistryURL
        
        // Create models directory
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.modelsDirectoryURL = documentsURL.appendingPathComponent("YOLOModels", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
        
        // Load models from database (with discovery for new files)
        Task {
            await refreshModels()
        }
    }
    
    // MARK: - Model Discovery (Database-First)
    
    /// Refresh available models from database + discover new ones
    func refreshModels() async {
        // 0. Clean up any duplicate models from previous runs
        persistence.cleanupDuplicates()
        
        // 1. Get all models from database (source of truth)
        var dbModels = persistence.allModels().map { $0.toModelInfo() }
        
        // 2. Discover any new bundled models not in DB
        let bundled = discoverBundledModels()
        for model in bundled {
            if !dbModels.contains(where: { $0.id == model.id || $0.name == model.name }) {
                if let _ = persistence.addModel(model, isSeeded: false) {
                    dbModels.append(model)
                }
            }
        }
        
        // 3. Discover any new local (downloaded) models not in DB
        // Note: Skip files that match existing model IDs (these are downloaded versions of remote models)
        let local = discoverLocalModels()
        for model in local {
            // Extract the base name without prefix to check if this is a downloaded remote model
            let baseName = model.name // e.g. "featured_yolo11_model" from "featured_yolo11_model.mlmodelc"
            
            // Skip if this file corresponds to an existing model (e.g., downloaded remote)
            let existsInDb = dbModels.contains(where: { 
                $0.id == model.id ||           // Same ID
                $0.id == baseName ||           // File name matches existing model ID
                $0.name == model.name          // Same name
            })
            
            if !existsInDb {
                if let _ = persistence.addModel(model, isSeeded: false) {
                    dbModels.append(model)
                }
            }
        }
        
        // 4. Fetch cloud registry if available
        if let registryURL = registryURL {
            let cloudModels = await fetchCloudRegistry(from: registryURL)
            for cloudModel in cloudModels {
                if !dbModels.contains(where: { $0.id == cloudModel.id }) {
                    if let _ = persistence.addModel(cloudModel, isSeeded: false) {
                        dbModels.append(cloudModel)
                    }
                }
            }
        }
        
        self.availableModels = dbModels
        
        // Initialize download states
        for model in dbModels {
            if downloadStates[model.id] == nil {
                downloadStates[model.id] = model.isDownloaded ? .downloaded : .notDownloaded
            }
        }
        
        // Debug: print what's in the database
        persistence.debugPrint()
    }
    
    /// Legacy method for compatibility
    func discoverModels() async {
        await refreshModels()
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
    
    // Note: Featured models are now defined in FeaturedModels enum (YOLOPersistenceManager.swift)
    // and seeded into the database on first launch
    
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
            let ext = url.pathExtension.lowercased()
            let tempWithExtURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext.isEmpty ? "mlmodel" : ext)
            
            try FileManager.default.moveItem(at: tempURL, to: tempWithExtURL)
            
            defer {
                try? FileManager.default.removeItem(at: tempWithExtURL)
            }
            
            // Destination URL for the compiled model
            let destURL = modelsDirectoryURL.appendingPathComponent("\(model.id).mlmodelc")
            
            // Handle zip files (extract first)
            var modelURL = tempWithExtURL
            var tempExtractDir: URL? = nil
            
            if ext == "zip" {
                let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
                tempExtractDir = extractDir
                
                // Unzip using Process (Foundation doesn't have built-in unzip)
                let unzipResult = try await unzipFile(at: tempWithExtURL, to: extractDir)
                guard unzipResult else {
                    throw YOLOModelError.loadFailed(underlying: NSError(domain: "YOLOModelManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to unzip model archive"]))
                }
                
                // Find the .mlpackage or .mlmodelc inside
                if let foundModel = try findModelInDirectory(extractDir) {
                    modelURL = foundModel
                } else {
                    throw YOLOModelError.loadFailed(underlying: NSError(domain: "YOLOModelManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "No .mlpackage or .mlmodelc found in zip"]))
                }
            }
            
            defer {
                if let dir = tempExtractDir {
                    try? FileManager.default.removeItem(at: dir)
                }
            }
            
            let modelExt = modelURL.pathExtension.lowercased()
            
            // Compile logic
            if modelExt == "mlmodel" || modelExt == "mlpackage" {
                let compiledURL = try await compileModel(at: modelURL)
                
                // If destination exists, remove it first
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                
                try FileManager.default.moveItem(at: compiledURL, to: destURL)
            } else if modelExt == "mlmodelc" {
                // Already compiled
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: modelURL, to: destURL)
            } else {
                throw YOLOModelError.loadFailed(underlying: NSError(domain: "YOLOModelManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported model extension: \(modelExt)"]))
            }
            
            // Update database with local path
            persistence.setLocalPath(destURL.path, for: model.id)
            
            downloadStates[model.id] = .downloaded
            await refreshModels()
            
        } catch {
            print("Download failed: \(error)")
            downloadStates[model.id] = .failed(error: error.localizedDescription)
        }
    }
    
    /// Unzip a file to a destination directory (cross-platform: macOS and iOS)
    private func unzipFile(at sourceURL: URL, to destURL: URL) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                #if os(macOS)
                // On macOS, use Process to call unzip
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = ["-o", "-q", sourceURL.path, "-d", destURL.path]
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(throwing: error)
                }
                #else
                // On iOS, use pure Swift zip extraction
                let result = Self.extractZipFile(at: sourceURL, to: destURL)
                continuation.resume(returning: result)
                #endif
            }
        }
    }
    
    /// Pure Swift zip extraction for iOS using ZIPFoundation-style manual extraction
    private nonisolated static func extractZipFile(at sourceURL: URL, to destinationURL: URL) -> Bool {
        guard let archive = ZipArchiveReader(url: sourceURL) else {
            print("Failed to open zip archive")
            return false
        }
        
        do {
            try archive.extractAll(to: destinationURL)
            return true
        } catch {
            print("Zip extraction failed: \(error)")
            return false
        }
    }
    
    /// Find a .mlpackage or .mlmodelc in a directory (recursively)
    private func findModelInDirectory(_ directory: URL) throws -> URL? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "mlpackage" || ext == "mlmodelc" {
                return fileURL
            }
        }
        return nil
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
            
            // Extract model specification
            let spec = Self.extractSpec(from: mlModel)
            
            self.loadedVisionModel = visionModel
            self.activeModel = model
            self.modelSpec = spec
            self.isLoading = false
            
        } catch {
            self.loadError = error.localizedDescription
            self.modelSpec = .empty
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
    
    /// Extract model specification from a loaded MLModel
    private nonisolated static func extractSpec(from model: MLModel) -> MLModelSpec {
        let description = model.modelDescription
        
        // Extract inputs
        let inputs: [MLFeatureSpec] = description.inputDescriptionsByName.map { name, feature in
            MLFeatureSpec(
                name: name,
                type: featureTypeName(feature.type),
                shape: extractShape(from: feature),
                description: nil
            )
        }.sorted { $0.name < $1.name }
        
        // Extract outputs
        let outputs: [MLFeatureSpec] = description.outputDescriptionsByName.map { name, feature in
            MLFeatureSpec(
                name: name,
                type: featureTypeName(feature.type),
                shape: extractShape(from: feature),
                description: nil
            )
        }.sorted { $0.name < $1.name }
        
        // Extract class labels if available
        var classLabels: [String]? = nil
        if let labelsKey = description.classLabels {
            switch labelsKey {
            case let stringLabels as [String]:
                classLabels = stringLabels
            case let intLabels as [Int64]:
                classLabels = intLabels.map { String($0) }
            default:
                break
            }
        }
        
        return MLModelSpec(
            inputs: inputs,
            outputs: outputs,
            author: description.metadata[.author] as? String,
            license: description.metadata[.license] as? String,
            modelDescription: description.metadata[.description] as? String,
            version: description.metadata[.versionString] as? String,
            classLabels: classLabels
        )
    }
    
    /// Convert MLFeatureType to human-readable string
    private nonisolated static func featureTypeName(_ type: MLFeatureType) -> String {
        switch type {
        case .invalid: return "Invalid"
        case .int64: return "Int64"
        case .double: return "Double"
        case .string: return "String"
        case .image: return "Image"
        case .multiArray: return "MultiArray"
        case .dictionary: return "Dictionary"
        case .sequence: return "Sequence"
        case .state: return "State"
        @unknown default: return "Unknown"
        }
    }
    
    /// Extract shape from feature description
    private nonisolated static func extractShape(from feature: MLFeatureDescription) -> [Int]? {
        switch feature.type {
        case .multiArray:
            if let constraint = feature.multiArrayConstraint {
                return constraint.shape.map { $0.intValue }
            }
        case .image:
            if let constraint = feature.imageConstraint {
                return [Int(constraint.pixelsWide), Int(constraint.pixelsHigh)]
            }
        default:
            break
        }
        return nil
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
        
        // Remove from database
        if let catalogEntry = persistence.model(withId: model.id) {
            persistence.deleteModel(catalogEntry)
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
        
        // Add to database
        _ = persistence.addModel(model, isSeeded: false)
        
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
