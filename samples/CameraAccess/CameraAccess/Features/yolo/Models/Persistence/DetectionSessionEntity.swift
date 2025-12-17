/*
 * DetectionSessionEntity.swift
 * CameraAccess
 *
 * SwiftData entity for tracking detection session analytics.
 * Records performance metrics and usage statistics per session.
 */

import Foundation
import SwiftData

/// Analytics record for a detection session
@Model
final class DetectionSessionEntity {
    // MARK: - Identity
    
    @Attribute(.unique) var id: UUID
    
    // MARK: - Foreign Key
    
    var modelId: String
    
    // MARK: - Timing
    
    var startedAt: Date
    var endedAt: Date?
    
    var durationSeconds: Double? {
        guard let end = endedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }
    
    // MARK: - Performance Metrics
    
    var totalDetections: Int = 0
    var framesProcessed: Int = 0
    var avgInferenceMs: Double = 0
    var maxInferenceMs: Double = 0
    var minInferenceMs: Double = Double.infinity
    
    // MARK: - Relationship
    
    var model: ModelCatalog?
    
    // MARK: - Init
    
    init(modelId: String, model: ModelCatalog? = nil) {
        self.id = UUID()
        self.modelId = modelId
        self.startedAt = Date()
        self.model = model
    }
    
    // MARK: - Recording
    
    /// Record a detection frame
    func recordFrame(detectionCount: Int, inferenceTimeMs: Double) {
        totalDetections += detectionCount
        framesProcessed += 1
        
        // Update inference time stats
        if inferenceTimeMs < minInferenceMs {
            minInferenceMs = inferenceTimeMs
        }
        if inferenceTimeMs > maxInferenceMs {
            maxInferenceMs = inferenceTimeMs
        }
        
        // Running average
        let total = avgInferenceMs * Double(framesProcessed - 1) + inferenceTimeMs
        avgInferenceMs = total / Double(framesProcessed)
    }
    
    /// End the session
    func endSession() {
        endedAt = Date()
    }
    
    // MARK: - Summary
    
    /// Get a human-readable summary of this session
    var summary: String {
        let duration = durationSeconds ?? 0
        let fps = duration > 0 ? Double(framesProcessed) / duration : 0
        return String(format: "%.1fs, %d frames (%.1f FPS), %d detections, avg %.1fms inference",
                      duration, framesProcessed, fps, totalDetections, avgInferenceMs)
    }
}
