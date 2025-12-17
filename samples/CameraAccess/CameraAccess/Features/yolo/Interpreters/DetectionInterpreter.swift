/*
 * DetectionInterpreter.swift
 * CameraAccess
 *
 * Protocol for interpreting raw YOLO detections into
 * domain-specific results.
 */

import Foundation

/// Result from a detection interpreter
struct InterpretedDetections {
    /// Raw detections that were processed
    let rawDetections: [YOLODetection]
    
    /// Summary text for display
    let summary: String
    
    /// Additional structured data (stored as JSON-encodable)
    let metadata: [String: Any]?
    
    /// Model type that produced this result
    let modelType: YOLOModelType
    
    init(rawDetections: [YOLODetection], summary: String, metadata: [String: Any]? = nil, modelType: YOLOModelType = .generic) {
        self.rawDetections = rawDetections
        self.summary = summary
        self.metadata = metadata
        self.modelType = modelType
    }
}

/// Protocol for interpreting YOLO detections
protocol DetectionInterpreter {
    /// The model types this interpreter supports
    static var supportedModelTypes: Set<YOLOModelType> { get }
    
    /// Interpret raw detections into a structured result
    func interpret(_ detections: [YOLODetection]) -> InterpretedDetections
    
    /// Display name for this interpreter
    var displayName: String { get }
}

/// Base implementation with default behaviors
extension DetectionInterpreter {
    var displayName: String {
        String(describing: type(of: self))
    }
}
