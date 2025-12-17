/*
 * InterpreterConfig.swift
 * CameraAccess
 *
 * SwiftData model for per-model interpreter configuration.
 * Stores custom settings for how detections are processed.
 */

import Foundation
import SwiftData

/// Per-model interpreter configuration
@Model
final class InterpreterConfig {
    // MARK: - Identity
    
    @Attribute(.unique) var modelId: String
    
    // MARK: - Common Settings
    
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
    /// e.g., for poker: {"showHandRanking": true, "autoAnalyze": true}
    var customSettingsJSON: String?
    
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
}
