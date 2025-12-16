/*
 * YOLOModelInfo.swift
 * CameraAccess
 *
 * Model metadata for YOLO detection models.
 */

import Foundation

/// Source of a YOLO model
enum YOLOModelSource: Codable, Equatable {
    case bundled(resourceName: String)
    case local(path: String)
    case remote(url: String)
    
    var displayName: String {
        switch self {
        case .bundled:
            return "Bundled"
        case .local:
            return "Local"
        case .remote:
            return "Cloud"
        }
    }
}

/// Information about a YOLO model
struct YOLOModelInfo: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let source: YOLOModelSource
    let version: String
    
    /// Size in bytes (for download progress), nil if unknown
    var sizeBytes: Int64?
    
    /// Whether this model has been downloaded (always true for bundled)
    var isDownloaded: Bool {
        switch source {
        case .bundled:
            return true
        case .local(let path):
            return FileManager.default.fileExists(atPath: path)
        case .remote:
            return localURL != nil && FileManager.default.fileExists(atPath: localURL!.path)
        }
    }
    
    /// Local URL where the model is stored
    var localURL: URL? {
        switch source {
        case .bundled(let resourceName):
            return Bundle.main.url(forResource: resourceName, withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: resourceName, withExtension: "mlpackage")
        case .local(let path):
            return URL(fileURLWithPath: path)
        case .remote:
            // Downloaded models are stored in Documents/YOLOModels/
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let modelsDir = documentsURL.appendingPathComponent("YOLOModels", isDirectory: true)
            return modelsDir.appendingPathComponent("\(id).mlmodelc")
        }
    }
}

/// Download state for a remote model
enum YOLOModelDownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case failed(error: String)
}
