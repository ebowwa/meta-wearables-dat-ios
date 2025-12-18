/*
 * InterpreterConfigEntity.swift
 * CameraAccess
 *
 * SwiftData entity for per-model interpreter configuration.
 * Stores how detections should be processed for each model.
 */

import Foundation
import SwiftData

/// Per-model interpreter configuration
@Model
final class InterpreterConfigEntity {
    // MARK: - Identity (references ModelCatalog)
    
    @Attribute(.unique) var modelId: String
    
    // MARK: - Detection Settings
    
    /// Non-maximum suppression threshold
    var nmsThreshold: Float = 0.45
    
    /// Maximum number of detections to return
    var maxDetections: Int = 100
    
    /// Minimum detection confidence
    var confidenceThreshold: Float = 0.5
    
    // MARK: - Display Settings
    
    /// Show confidence percentage on labels
    var showConfidence: Bool = true
    
    /// Show bounding boxes
    var showBoundingBoxes: Bool = true
    
    /// Color scheme for overlays (JSON: {"person": "#00FF00", ...})
    var colorSchemeJSON: String?
    
    // MARK: - Model-Specific Settings
    
    /// JSON blob for model-specific interpreter settings
    /// e.g., for faceClassification: {"showAgeEstimate": true, "autoAnalyze": true}
    var customSettingsJSON: String?
    
    // MARK: - Relationship
    
    var model: ModelCatalog?
    
    // MARK: - Init
    
    init(modelId: String) {
        self.modelId = modelId
    }
    
    // MARK: - JSON Helpers
    
    /// Get custom settings as dictionary
    func customSettings() -> [String: Any]? {
        guard let json = customSettingsJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }
    
    /// Set custom settings from dictionary
    func setCustomSettings(_ settings: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: settings),
           let json = String(data: data, encoding: .utf8) {
            customSettingsJSON = json
        }
    }
    
    /// Get color scheme as dictionary
    func colorScheme() -> [String: String]? {
        guard let json = colorSchemeJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        return dict
    }
    
    /// Set color scheme from dictionary
    func setColorScheme(_ colors: [String: String]) {
        if let data = try? JSONSerialization.data(withJSONObject: colors),
           let json = String(data: data, encoding: .utf8) {
            colorSchemeJSON = json
        }
    }
}
