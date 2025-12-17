/*
 * YOLOModelRecord.swift
 * CameraAccess
 *
 * SwiftData model for persisting YOLO model metadata,
 * user preferences, and usage statistics.
 */

import Foundation
import SwiftData

/// Persistent record for a YOLO model
@Model
final class YOLOModelRecord {
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
    /// Local path where model is stored (after download)
    var localPath: String?
    
    // MARK: - Model Type
    
    /// Type of model: "generic", "poker", "faceClassification", "custom"
    var modelTypeRaw: String
    
    var modelType: YOLOModelType {
        get { YOLOModelType(rawValue: modelTypeRaw) ?? .generic }
        set { modelTypeRaw = newValue.rawValue }
    }
    
    // MARK: - User Preferences
    
    var isFavorite: Bool = false
    var isHidden: Bool = false
    var confidenceThreshold: Float = 0.5
    
    // MARK: - Usage Statistics
    
    var downloadDate: Date?
    var lastUsedDate: Date?
    var usageCount: Int = 0
    
    // MARK: - Interpreter Configuration
    
    /// JSON-encoded custom settings for the interpreter
    var interpreterConfigJSON: String?
    
    // MARK: - Relationships
    
    @Relationship(deleteRule: .cascade, inverse: \DetectionSession.model)
    var sessions: [DetectionSession]? = []
    
    // MARK: - Init
    
    init(id: String, name: String, modelDescription: String = "", version: String = "1.0", sourceType: String = "local", sourceLocation: String? = nil, modelType: YOLOModelType = .generic) {
        self.id = id
        self.name = name
        self.modelDescription = modelDescription
        self.version = version
        self.sourceType = sourceType
        self.sourceLocation = sourceLocation
        self.modelTypeRaw = modelType.rawValue
    }
    
    // MARK: - Conversion
    
    /// Create from a YOLOModelInfo
    convenience init(from info: YOLOModelInfo) {
        let (sourceType, sourceLocation) = Self.extractSource(info.source)
        self.init(
            id: info.id,
            name: info.name,
            modelDescription: info.description,
            version: info.version,
            sourceType: sourceType,
            sourceLocation: sourceLocation,
            modelType: info.modelType
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
