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

// MARK: - CoreML Model Specification

/// Represents a single feature (input or output) of a CoreML model
struct MLFeatureSpec: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let type: String
    let shape: [Int]?
    let description: String?
    
    var shapeDescription: String {
        guard let shape = shape else { return "N/A" }
        return shape.map { String($0) }.joined(separator: " × ")
    }
    
    var summary: String {
        var result = "\(name): \(type)"
        if let shape = shape, !shape.isEmpty {
            result += " [\(shapeDescription)]"
        }
        return result
    }
}

/// Complete specification of a CoreML model's inputs, outputs, and metadata
struct MLModelSpec: Equatable {
    let inputs: [MLFeatureSpec]
    let outputs: [MLFeatureSpec]
    let author: String?
    let license: String?
    let modelDescription: String?
    let version: String?
    let classLabels: [String]?
    
    /// Human-readable summary of the model
    var summary: String {
        var lines: [String] = []
        
        if let desc = modelDescription, !desc.isEmpty {
            lines.append("Description: \(desc)")
        }
        if let author = author, !author.isEmpty {
            lines.append("Author: \(author)")
        }
        if let version = version, !version.isEmpty {
            lines.append("Version: \(version)")
        }
        
        lines.append("")
        lines.append("Inputs (\(inputs.count)):")
        for input in inputs {
            lines.append("  • \(input.summary)")
        }
        
        lines.append("")
        lines.append("Outputs (\(outputs.count)):")
        for output in outputs {
            lines.append("  • \(output.summary)")
        }
        
        if let labels = classLabels, !labels.isEmpty {
            lines.append("")
            lines.append("Class Labels (\(labels.count)): \(labels.prefix(10).joined(separator: ", "))\(labels.count > 10 ? "..." : "")")
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Empty spec for when no model is loaded
    static let empty = MLModelSpec(
        inputs: [],
        outputs: [],
        author: nil,
        license: nil,
        modelDescription: nil,
        version: nil,
        classLabels: nil
    )
}
