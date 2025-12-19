//
//  DetectionTrainingBridge.swift
//  CameraAccess
//
//  Bridges YOLO detections to the KNN training system.
//  Enables: "this YOLO 'person' detection is actually 'Alice'" workflow.
//

import Foundation
import UIKit
import CoreGraphics

/// Result of a prediction on a detection region
struct DetectionPrediction {
    let detection: YOLODetection
    let knnResult: KNNResult
    let croppedImage: UIImage
}

/// Bridges YOLO detections with on-device KNN training
///
/// Usage:
/// ```
/// // Train: Label a detected person as "Alice"
/// await bridge.trainFromDetection(detection, in: fullImage, withLabel: "Alice")
///
/// // Predict: Who is this detected person?
/// let prediction = await bridge.predictForDetection(detection, in: fullImage)
/// ```
@MainActor
class DetectionTrainingBridge: ObservableObject {
    
    // MARK: - Dependencies
    
    private let trainingService: TrainingService
    
    // MARK: - Published State
    
    @Published var lastCroppedImage: UIImage?
    @Published var lastPrediction: DetectionPrediction?
    @Published var isProcessing = false
    
    // MARK: - Configuration
    
    /// Minimum crop size (detections smaller than this get upscaled)
    var minimumCropSize: CGFloat = 64
    
    /// Padding around detection box (0.0 = no padding, 0.1 = 10% padding)
    var cropPadding: CGFloat = 0.1
    
    // MARK: - Init
    
    /// Create bridge with an existing TrainingService
    init(trainingService: TrainingService) {
        self.trainingService = trainingService
    }
    
    /// Convenience initializer that creates its own TrainingService
    convenience init() {
        self.init(trainingService: TrainingService())
    }
    
    // MARK: - Core API
    
    /// Train KNN on a cropped detection region with a custom label
    ///
    /// - Parameters:
    ///   - detection: The YOLO detection to train on
    ///   - image: The full image containing the detection
    ///   - customLabel: The label to assign (e.g., "Alice", "Bob", "My Dog")
    /// - Returns: True if training succeeded
    func trainFromDetection(
        _ detection: YOLODetection,
        in image: UIImage,
        withLabel customLabel: String
    ) async -> Bool {
        guard !customLabel.isEmpty else {
            print("❌ Cannot train with empty label")
            return false
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Crop the detection region
        guard let croppedImage = cropDetection(detection, from: image) else {
            print("❌ Failed to crop detection region")
            return false
        }
        
        lastCroppedImage = croppedImage
        
        // Train KNN on the cropped image
        let success = await trainingService.addTrainingSample(image: croppedImage, label: customLabel)
        
        if success {
            print("✅ Trained '\(customLabel)' from \(detection.label) detection")
        }
        
        return success
    }
    
    /// Predict custom label for a detection region
    ///
    /// - Parameters:
    ///   - detection: The YOLO detection to classify
    ///   - image: The full image containing the detection
    /// - Returns: Prediction result with custom label, or nil if prediction failed
    func predictForDetection(
        _ detection: YOLODetection,
        in image: UIImage
    ) async -> DetectionPrediction? {
        isProcessing = true
        defer { isProcessing = false }
        
        // Crop the detection region
        guard let croppedImage = cropDetection(detection, from: image) else {
            return nil
        }
        
        lastCroppedImage = croppedImage
        
        // Predict using KNN
        guard let knnResult = await trainingService.predict(image: croppedImage) else {
            return nil
        }
        
        let prediction = DetectionPrediction(
            detection: detection,
            knnResult: knnResult,
            croppedImage: croppedImage
        )
        
        lastPrediction = prediction
        return prediction
    }
    
    /// Predict custom labels for all detections in an image
    ///
    /// - Parameters:
    ///   - detections: Array of YOLO detections
    ///   - image: The full image containing the detections
    /// - Returns: Array of predictions (may be fewer than detections if some fail)
    func predictForAllDetections(
        _ detections: [YOLODetection],
        in image: UIImage
    ) async -> [DetectionPrediction] {
        var predictions: [DetectionPrediction] = []
        
        for detection in detections {
            if let prediction = await predictForDetection(detection, in: image) {
                predictions.append(prediction)
            }
        }
        
        return predictions
    }
    
    // MARK: - Cropping
    
    /// Crop a detection region from the full image
    ///
    /// - Parameters:
    ///   - detection: The detection with normalized bounding box (0-1)
    ///   - image: The full source image
    /// - Returns: Cropped UIImage of just the detection region
    func cropDetection(_ detection: YOLODetection, from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        
        // Convert normalized bbox to pixel coordinates
        // Vision uses bottom-left origin, but bounding box is already in 0-1 normalized coords
        var cropRect = CGRect(
            x: detection.boundingBox.origin.x * imageWidth,
            y: (1 - detection.boundingBox.origin.y - detection.boundingBox.height) * imageHeight,
            width: detection.boundingBox.width * imageWidth,
            height: detection.boundingBox.height * imageHeight
        )
        
        // Add padding
        if cropPadding > 0 {
            let paddingX = cropRect.width * cropPadding
            let paddingY = cropRect.height * cropPadding
            cropRect = cropRect.insetBy(dx: -paddingX, dy: -paddingY)
        }
        
        // Clamp to image bounds
        cropRect = cropRect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        
        guard !cropRect.isEmpty, cropRect.width > 0, cropRect.height > 0 else {
            return nil
        }
        
        // Crop the image
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return nil
        }
        
        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    // MARK: - Utilities
    
    /// Get all trained classes from the underlying KNN
    var trainedClasses: [String] {
        trainingService.trainedClasses
    }
    
    /// Get total number of training samples
    var totalSamples: Int {
        trainingService.trainingSamples
    }
    
    /// Check if we have any training data
    var hasTrainingData: Bool {
        totalSamples > 0
    }
    
    /// Remove all samples for a label
    func removeSamples(for label: String) {
        trainingService.removeSamples(for: label)
    }
    
    /// Reset all training data
    func resetModel() {
        trainingService.resetModel()
        lastCroppedImage = nil
        lastPrediction = nil
    }
    
    /// Access the underlying training service (for advanced use)
    var training: TrainingService {
        trainingService
    }
}

// MARK: - YOLODetection Extension

extension YOLODetection {
    /// Get a display label combining YOLO class with custom KNN label
    func displayLabel(withCustomLabel customLabel: String?, confidence: Float?) -> String {
        if let custom = customLabel, let conf = confidence, conf > 0.5 {
            return "\(custom) (\(label))"
        }
        return label
    }
}
