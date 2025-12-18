/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreML
import Foundation

/// Decodes raw YOLO11 tensor output into DetectedCard objects
/// YOLO11 outputs a tensor of shape [1, numClasses+4, numBoxes] or transposed
/// where each detection contains: [x_center, y_center, width, height, class_scores...]
class YOLOOutputDecoder {
    
    static let shared = YOLOOutputDecoder()
    
    /// Confidence threshold for detections (must be > 0.5 since sigmoid(0)=0.5)
    var confidenceThreshold: Float = 0.6
    
    /// IoU threshold for Non-Maximum Suppression
    var iouThreshold: Float = 0.4
    
    /// Minimum box size as fraction of image (filter tiny/garbage boxes)
    var minBoxSize: Float = 0.02
    
    /// Number of classes (52 poker cards)
    private let numClasses = 52
    
    /// YOLO11 poker card class labels in Roboflow alphabetical order (uppercase)
    /// Format: rank + suit (e.g., "10C" = 10 of clubs)
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
    
    /// Sigmoid activation function
    private func sigmoid(_ x: Float) -> Float {
        return 1.0 / (1.0 + exp(-x))
    }
    
    /// Decode YOLO output tensor into DetectedCard objects
    func decode(featureValue: MLFeatureValue) -> [DetectedCard] {
        guard let multiArray = featureValue.multiArrayValue else {
            print("❌ YOLOOutputDecoder: No multiArray in feature value")
            return []
        }
        
        let shape = multiArray.shape.map { $0.intValue }
        print("📐 YOLO output shape: \(shape)")
        
        // YOLO11 output is typically [1, 56, 8400] or [1, 8400, 56]
        // 56 = 4 bbox coords + 52 class scores
        // 8400 = number of anchor boxes
        
        guard shape.count >= 2 else {
            print("❌ YOLOOutputDecoder: Unexpected shape dimensions")
            return []
        }
        
        // Determine orientation: [batch, features, boxes] or [batch, boxes, features]
        let featuresDim: Int
        let boxesDim: Int
        let isTransposed: Bool
        
        if shape.count == 3 {
            // Shape is [batch, dim1, dim2]
            if shape[1] == numClasses + 4 {
                // [1, 56, 8400] - features first
                featuresDim = shape[1]
                boxesDim = shape[2]
                isTransposed = false
            } else if shape[2] == numClasses + 4 {
                // [1, 8400, 56] - boxes first
                featuresDim = shape[2]
                boxesDim = shape[1]
                isTransposed = true
            } else {
                print("❌ YOLOOutputDecoder: Cannot determine tensor orientation. Expected 56 features, got \(shape[1]) and \(shape[2])")
                return []
            }
        } else {
            print("❌ YOLOOutputDecoder: Expected 3D tensor, got \(shape.count)D")
            return []
        }
        
        print("📊 Decoding \(boxesDim) boxes with \(featuresDim) features (transposed: \(isTransposed))")
        
        var rawDetections: [(box: CGRect, classIndex: Int, confidence: Float)] = []
        
        let pointer = multiArray.dataPointer.assumingMemoryBound(to: Float.self)
        
        var globalMaxScore: Float = 0
        var globalMaxRawScore: Float = -Float.infinity
        
        for boxIdx in 0..<boxesDim {
            // Extract bbox coordinates and class scores for this box
            var x: Float = 0, y: Float = 0, w: Float = 0, h: Float = 0
            var classScores: [Float] = Array(repeating: 0, count: numClasses)
            
            for featIdx in 0..<featuresDim {
                let value: Float
                if isTransposed {
                    // [1, boxes, features]
                    value = pointer[boxIdx * featuresDim + featIdx]
                } else {
                    // [1, features, boxes]
                    value = pointer[featIdx * boxesDim + boxIdx]
                }
                
                if featIdx == 0 { x = value }
                else if featIdx == 1 { y = value }
                else if featIdx == 2 { w = value }
                else if featIdx == 3 { h = value }
                else if featIdx - 4 < numClasses {
                    // Apply sigmoid to convert logits to probabilities
                    classScores[featIdx - 4] = sigmoid(value)
                    if value > globalMaxRawScore { globalMaxRawScore = value }
                }
            }
            
            // Find best class
            var maxScore: Float = 0
            var maxClassIndex = 0
            for (idx, score) in classScores.enumerated() {
                if score > maxScore {
                    maxScore = score
                    maxClassIndex = idx
                }
            }
            
            if maxScore > globalMaxScore { globalMaxScore = maxScore }
            
            // Apply confidence threshold and box size validation
            if maxScore >= confidenceThreshold {
                // Convert center-format to corner-format
                // (YOLO outputs are in pixel coords based on 640x640 input)
                let inputSize: Float = 640.0
                let normalizedW = w / inputSize
                let normalizedH = h / inputSize
                
                // Filter out tiny boxes (likely garbage detections)
                guard normalizedW >= minBoxSize && normalizedH >= minBoxSize else { continue }
                
                // Filter out invalid/huge boxes
                guard normalizedW <= 1.0 && normalizedH <= 1.0 else { continue }
                guard x >= 0 && y >= 0 && x <= inputSize && y <= inputSize else { continue }
                
                let box = CGRect(
                    x: CGFloat((x - w / 2) / inputSize),
                    y: CGFloat((y - h / 2) / inputSize),
                    width: CGFloat(normalizedW),
                    height: CGFloat(normalizedH)
                )
                rawDetections.append((box: box, classIndex: maxClassIndex, confidence: maxScore))
            }
        }
        
        print("📊 Max raw score: \(globalMaxRawScore), Max sigmoid score: \(globalMaxScore)")
        print("📊 Found \(rawDetections.count) detections above threshold \(confidenceThreshold)")
        
        // Apply Non-Maximum Suppression
        let nmsDetections = applyNMS(rawDetections)
        
        print("📊 After NMS: \(nmsDetections.count) detections")
        
        // Convert to DetectedCard
        return nmsDetections.compactMap { detection in
            guard detection.classIndex < classLabels.count else { return nil }
            let label = classLabels[detection.classIndex]
            guard let card = PokerCard.fromYOLOLabel(label) else { return nil }
            
            print("🔍 Decoded: \(card.displayName) (\(Int(detection.confidence * 100))%)")
            
            return DetectedCard(
                card: card,
                confidence: detection.confidence,
                boundingBox: detection.box  // Already normalized to 0-1
            )
        }
    }
    
    /// Apply Non-Maximum Suppression to filter overlapping boxes
    private func applyNMS(_ detections: [(box: CGRect, classIndex: Int, confidence: Float)]) -> [(box: CGRect, classIndex: Int, confidence: Float)] {
        guard !detections.isEmpty else { return [] }
        
        // Sort by confidence (descending)
        let sorted = detections.sorted { $0.confidence > $1.confidence }
        
        var kept: [(box: CGRect, classIndex: Int, confidence: Float)] = []
        var suppressed = Set<Int>()
        
        for (i, detection) in sorted.enumerated() {
            guard !suppressed.contains(i) else { continue }
            
            kept.append(detection)
            
            // Suppress overlapping boxes with same class
            for j in (i + 1)..<sorted.count {
                guard !suppressed.contains(j) else { continue }
                
                if sorted[j].classIndex == detection.classIndex {
                    let iou = calculateIoU(detection.box, sorted[j].box)
                    if iou > iouThreshold {
                        suppressed.insert(j)
                    }
                }
            }
        }
        
        return kept
    }
    
    /// Calculate Intersection over Union
    private func calculateIoU(_ box1: CGRect, _ box2: CGRect) -> Float {
        let intersection = box1.intersection(box2)
        
        guard !intersection.isNull else { return 0 }
        
        let intersectionArea = intersection.width * intersection.height
        let unionArea = box1.width * box1.height + box2.width * box2.height - intersectionArea
        
        guard unionArea > 0 else { return 0 }
        
        return Float(intersectionArea / unionArea)
    }
}
