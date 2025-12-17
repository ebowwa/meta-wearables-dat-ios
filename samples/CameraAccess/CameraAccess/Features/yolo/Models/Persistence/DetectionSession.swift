/*
 * DetectionSession.swift
 * CameraAccess
 *
 * SwiftData model for tracking detection session analytics
 * including performance metrics and usage statistics.
 */

import Foundation
import SwiftData

/// Analytics record for a detection session
@Model
final class DetectionSession {
    // MARK: - Identity
    
    var id: UUID = UUID()
    
    // MARK: - Timing
    
    var startDate: Date
    var endDate: Date?
    
    var durationSeconds: Double? {
        guard let end = endDate else { return nil }
        return end.timeIntervalSince(startDate)
    }
    
    // MARK: - Performance Metrics
    
    var totalDetections: Int = 0
    var framesProcessed: Int = 0
    var avgInferenceTimeMs: Double = 0
    var maxInferenceTimeMs: Double = 0
    var minInferenceTimeMs: Double = Double.infinity
    
    // MARK: - Relationships
    
    var model: YOLOModelRecord?
    
    // MARK: - Init
    
    init(startDate: Date = Date(), model: YOLOModelRecord? = nil) {
        self.startDate = startDate
        self.model = model
    }
    
    // MARK: - Recording
    
    /// Record a detection frame
    func recordFrame(detectionCount: Int, inferenceTimeMs: Double) {
        totalDetections += detectionCount
        framesProcessed += 1
        
        // Update inference time stats
        if inferenceTimeMs < minInferenceTimeMs {
            minInferenceTimeMs = inferenceTimeMs
        }
        if inferenceTimeMs > maxInferenceTimeMs {
            maxInferenceTimeMs = inferenceTimeMs
        }
        
        // Running average
        let total = avgInferenceTimeMs * Double(framesProcessed - 1) + inferenceTimeMs
        avgInferenceTimeMs = total / Double(framesProcessed)
    }
    
    /// End the session
    func endSession() {
        endDate = Date()
    }
}
