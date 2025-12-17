/*
 * ModelCatalog.swift
 * CameraAccess
 *
 * SwiftData entity for the model catalog - source of truth for all YOLO models.
 * This is the central entity that other tables reference.
 */

import Foundation
import SwiftData

/// Source of truth for all YOLO models in the system
@Model
final class ModelCatalog {
    // MARK: - Identity
    
    @Attribute(.unique) var id: String
    var name: String
    var modelDescription: String
    var version: String
    
    // MARK: - Source
    
    /// Type of source: "bundled", "local", "remote"
    var sourceType: String
    /// URL or path for the source
    var sourceLocation: String?
    /// Local path where model is stored (after download for remote models)
    var localPath: String?
    
    // MARK: - Model Type
    
    /// Type of model: "generic", "poker", "faceClassification", "custom"
    var modelTypeRaw: String
    
    var modelType: YOLOModelType {
        get { YOLOModelType(rawValue: modelTypeRaw) ?? .generic }
        set { modelTypeRaw = newValue.rawValue }
    }
    
    // MARK: - Metadata
    
    /// Whether this model came from seed data (vs user-added)
    var isSeeded: Bool = false
    /// File size in bytes (for download UI)
    var sizeBytes: Int64?
    /// When this entry was created
    var createdAt: Date
    
    // MARK: - Relationships
    
    @Relationship(deleteRule: .cascade)
    var interpreterConfig: InterpreterConfigEntity?
    
    @Relationship(deleteRule: .cascade)
    var userPreferences: UserPreferences?
    
    @Relationship(deleteRule: .cascade, inverse: \DetectionSessionEntity.model)
    var sessions: [DetectionSessionEntity]? = []
    
    // MARK: - Init
    
    init(
        id: String,
        name: String,
        modelDescription: String = "",
        version: String = "1.0",
        sourceType: String = "bundled",
        sourceLocation: String? = nil,
        modelType: YOLOModelType = .generic,
        isSeeded: Bool = false,
        sizeBytes: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.modelDescription = modelDescription
        self.version = version
        self.sourceType = sourceType
        self.sourceLocation = sourceLocation
        self.modelTypeRaw = modelType.rawValue
        self.isSeeded = isSeeded
        self.sizeBytes = sizeBytes
        self.createdAt = Date()
    }
    
    // MARK: - Convenience
    
    /// Create from a YOLOModelInfo struct
    convenience init(from info: YOLOModelInfo, isSeeded: Bool = false) {
        let (sourceType, sourceLocation) = Self.extractSource(info.source)
        self.init(
            id: info.id,
            name: info.name,
            modelDescription: info.description,
            version: info.version,
            sourceType: sourceType,
            sourceLocation: sourceLocation,
            modelType: info.modelType,
            isSeeded: isSeeded,
            sizeBytes: info.sizeBytes
        )
    }
    
    /// Convert back to YOLOModelInfo for compatibility
    func toModelInfo() -> YOLOModelInfo {
        let source: YOLOModelSource
        switch sourceType {
        case "bundled":
            source = .bundled(resourceName: sourceLocation ?? name)
        case "remote":
            source = .remote(url: sourceLocation ?? "")
        default:
            source = .local(path: localPath ?? sourceLocation ?? "")
        }
        
        return YOLOModelInfo(
            id: id,
            name: name,
            description: modelDescription,
            source: source,
            version: version,
            modelType: modelType,
            sizeBytes: sizeBytes
        )
    }
    
    private static func extractSource(_ source: YOLOModelSource) -> (String, String?) {
        switch source {
        case .bundled(let resourceName):
            return ("bundled", resourceName)
        case .local(let path):
            return ("local", path)
        case .remote(let url):
            return ("remote", url)
        }
    }
}
