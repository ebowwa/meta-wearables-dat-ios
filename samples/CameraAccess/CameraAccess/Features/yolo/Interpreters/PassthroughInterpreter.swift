/*
 * PassthroughInterpreter.swift
 * CameraAccess
 *
 * Default interpreter that passes detections through unchanged.
 * Used for generic object detection models.
 */

import Foundation

/// Default interpreter - returns detections as-is with a summary
final class PassthroughInterpreter: DetectionInterpreter {
    
    static let supportedModelTypes: Set<YOLOModelType> = [.generic, .custom]
    
    var displayName: String { "Object Detection" }
    
    func interpret(_ detections: [YOLODetection]) -> InterpretedDetections {
        // Group by label and count
        var counts: [String: Int] = [:]
        for detection in detections {
            counts[detection.label, default: 0] += 1
        }
        
        // Build summary
        let summary: String
        if counts.isEmpty {
            summary = "No objects detected"
        } else {
            let items = counts.sorted { $0.value > $1.value }
                .map { "\($0.value) \($0.key)\($0.value > 1 ? "s" : "")" }
            summary = items.joined(separator: ", ")
        }
        
        return InterpretedDetections(
            rawDetections: detections,
            summary: summary,
            metadata: ["counts": counts],
            modelType: .generic
        )
    }
}
