/*
 * YOLOOutputDecoder.swift
 * CameraAccess
 *
 * Decodes raw YOLO model output tensors into bounding boxes and class predictions.
 * Handles YOLO11 output format: [1 × (4 + num_classes) × num_predictions]
 */

import Foundation
import CoreML
import Vision

/// Decodes raw YOLO output tensors into DetectedCard results
class YOLOOutputDecoder {
    
    static let shared = YOLOOutputDecoder()
    
    /// Number of classes the model was trained on
    let numClasses: Int = 52
    
    /// Input image size the model expects
    let inputSize: CGFloat = 640.0
    
    /// Confidence threshold for detections
    var confidenceThreshold: Float = 0.25
    
    /// IoU threshold for Non-Maximum Suppression
    var iouThreshold: Float = 0.45
    
    /// Maximum number of detections to return
    var maxDetections: Int = 20
    
    /// Default poker card labels (52 cards) - Roboflow alphabetical order
    private let classLabels: [String] = [
        "10C", "10D", "10H", "10S",
        "2C", "2D", "2H", "2S",
        "3C", "3D", "3H", "3S",
        "4C", "4D", "4H", "4S",
        "5C", "5D", "5H", "5S",
        "6C", "6D", "6H", "6S",
        "7C", "7D", "7H", "7S",
        "8C", "8D", "8H", "8S",
        "9C", "9D", "9H", "9S",
        "AC", "AD", "AH", "AS",
        "JC", "JD", "JH", "JS",
        "KC", "KD", "KH", "KS",
        "QC", "QD", "QH", "QS"
    ]
    
    private init() {}
    
    // MARK: - Decode
    
    /// Decode MLFeatureValue into DetectedCard array
    func decode(featureValue: MLFeatureValue) -> [DetectedCard] {
        guard let multiArray = featureValue.multiArrayValue else {
            print("🔍 YOLO Decoder: No multiarray in observation")
            return []
        }
        
        return decode(multiArray: multiArray)
    }
    
    /// Decode raw MLMultiArray output
    func decode(multiArray: MLMultiArray) -> [DetectedCard] {
        let shape = multiArray.shape.map { $0.intValue }
        print("🔍 YOLO Decoder: MultiArray shape = \(shape)")
        
        // Expected shape: [1, 56, 8400] for 52 classes
        // 56 = 4 (x, y, w, h) + 52 (class scores)
        guard shape.count >= 2 else {
            print("🔍 YOLO Decoder: Unexpected shape")
            return []
        }
        
        let numFeatures = shape.count == 3 ? shape[1] : shape[0]
        let numPredictions = shape.count == 3 ? shape[2] : shape[1]
        
        print("🔍 YOLO Decoder: \(numFeatures) features, \(numPredictions) predictions")
        
        // Extract raw detections
        var rawDetections: [(box: CGRect, classId: Int, confidence: Float)] = []
        
        let pointer = UnsafeMutablePointer<Float>(OpaquePointer(multiArray.dataPointer))
        let strides = multiArray.strides.map { $0.intValue }
        
        for i in 0..<numPredictions {
            // Get bounding box (x_center, y_center, width, height)
            let xCenter: Float
            let yCenter: Float
            let width: Float
            let height: Float
            
            if shape.count == 3 {
                // Shape [1, 56, 8400]
                xCenter = pointer[0 * strides[1] + i]
                yCenter = pointer[1 * strides[1] + i]
                width = pointer[2 * strides[1] + i]
                height = pointer[3 * strides[1] + i]
            } else {
                // Shape [56, 8400]
                xCenter = pointer[0 * strides[0] + i]
                yCenter = pointer[1 * strides[0] + i]
                width = pointer[2 * strides[0] + i]
                height = pointer[3 * strides[0] + i]
            }
            
            // Find best class
            var bestClassId = 0
            var bestScore: Float = 0
            
            for c in 0..<numClasses {
                let score: Float
                if shape.count == 3 {
                    score = pointer[(4 + c) * strides[1] + i]
                } else {
                    score = pointer[(4 + c) * strides[0] + i]
                }
                
                if score > bestScore {
                    bestScore = score
                    bestClassId = c
                }
            }
            
            // Filter by confidence
            guard bestScore >= confidenceThreshold else { continue }
            
            // Convert to normalized coordinates (0-1)
            let x = CGFloat(xCenter / Float(inputSize))
            let y = CGFloat(yCenter / Float(inputSize))
            let w = CGFloat(width / Float(inputSize))
            let h = CGFloat(height / Float(inputSize))
            
            // Filter out invalid boxes
            guard w > 0.01 && h > 0.01 && w < 1.0 && h < 1.0 else { continue }
            guard x > 0 && y > 0 && x < 1.0 && y < 1.0 else { continue }
            
            // Convert from center format to corner format
            let box = CGRect(
                x: x - w / 2,
                y: y - h / 2,
                width: w,
                height: h
            )
            
            rawDetections.append((box: box, classId: bestClassId, confidence: bestScore))
        }
        
        print("🔍 YOLO Decoder: \(rawDetections.count) raw detections above threshold")
        
        // Apply Non-Maximum Suppression
        let nmsDetections = nonMaxSuppression(rawDetections)
        
        print("🔍 YOLO Decoder: \(nmsDetections.count) after NMS")
        
        // Convert to DetectedCard
        return nmsDetections.prefix(maxDetections).compactMap { detection in
            let label = detection.classId < classLabels.count
                ? classLabels[detection.classId]
                : "class_\(detection.classId)"
            
            guard let card = PokerCard.fromYOLOLabel(label) else { return nil }
            
            print("🔍 Decoded: \(card.displayName) (\(Int(detection.confidence * 100))%)")
            
            return DetectedCard(
                card: card,
                confidence: detection.confidence,
                boundingBox: detection.box
            )
        }
    }
    
    // MARK: - NMS
    
    private func nonMaxSuppression(_ detections: [(box: CGRect, classId: Int, confidence: Float)]) -> [(box: CGRect, classId: Int, confidence: Float)] {
        // Sort by confidence (highest first)
        var sorted = detections.sorted { $0.confidence > $1.confidence }
        var kept: [(box: CGRect, classId: Int, confidence: Float)] = []
        
        while !sorted.isEmpty {
            let best = sorted.removeFirst()
            kept.append(best)
            
            // Remove overlapping boxes of the same class
            sorted = sorted.filter { detection in
                if detection.classId != best.classId {
                    return true
                }
                return iou(best.box, detection.box) < iouThreshold
            }
        }
        
        return kept
    }
    
    /// Calculate Intersection over Union
    private func iou(_ a: CGRect, _ b: CGRect) -> Float {
        let intersection = a.intersection(b)
        if intersection.isNull { return 0 }
        
        let intersectionArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        
        return Float(intersectionArea / unionArea)
    }
}
