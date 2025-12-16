/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreML
import UIKit
import Vision

/// Service for real-time race classification using YOLOv8 CoreML model
/// Based on FairFace dataset with 7 balanced ethnicity categories
@MainActor
class RaceClassificationService {
    
    static let shared = RaceClassificationService()
    
    /// Minimum confidence threshold for classifications (0-1)
    var confidenceThreshold: Float = 0.3
    
    /// Whether the service is ready to perform classifications
    private(set) var isReady = false
    
    /// Error from loading the model, if any
    private(set) var loadError: Error?
    
    private var model: VNCoreMLModel?
    
    /// Model name (without extension)
    private let modelName = "Race-CLS-FairFace_yolov8n"
    
    /// FairFace category labels in order (matching model output indices)
    private let categoryLabels: [RaceCategory] = [
        .black,
        .eastAsian,
        .indian,
        .latinoHispanic,
        .middleEastern,
        .southeastAsian,
        .white
    ]
    
    private init() {
        Task {
            await loadModel()
        }
    }
    
    /// Load the YOLOv8 race classification model
    func loadModel() async {
        do {
            // Try to load the mlpackage or compiled mlmodelc from the app bundle
            guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") ??
                                 Bundle.main.url(forResource: modelName, withExtension: "mlpackage") else {
                throw RaceClassificationError.modelNotFound
            }
            
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine  // Optimize for on-device ML
            
            let mlModel = try await MLModel.load(contentsOf: modelURL, configuration: config)
            self.model = try VNCoreMLModel(for: mlModel)
            self.isReady = true
            self.loadError = nil
            
            print("✅ Race Classification model loaded successfully")
        } catch {
            self.loadError = error
            self.isReady = false
            print("❌ Failed to load Race Classification model: \(error.localizedDescription)")
        }
    }
    
    /// Classify the face in the given image
    /// - Parameter image: UIImage from video frame
    /// - Returns: Classification result with category and confidence scores
    func classify(image: UIImage) async -> ClassifiedFace? {
        guard isReady, let model = model else {
            return nil
        }
        
        guard let cgImage = image.cgImage else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { [weak self] request, error in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }
                
                guard error == nil else {
                    print("Classification error: \(error!.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                
                // Handle classification results
                if let results = request.results as? [VNClassificationObservation] {
                    let result = self.parseClassificationResults(results)
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            
            // Configure for classification
            request.imageCropAndScaleOption = .centerCrop
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("Vision request failed: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
    
    /// Parse VNClassificationObservation results into our model
    private func parseClassificationResults(_ observations: [VNClassificationObservation]) -> ClassifiedFace? {
        guard !observations.isEmpty else { return nil }
        
        // Build confidence dictionary
        var allConfidences: [RaceCategory: Float] = [:]
        
        for observation in observations {
            // Try to parse the identifier as a category
            if let category = RaceCategory.fromLabel(observation.identifier) {
                allConfidences[category] = observation.confidence
            } else if let index = Int(observation.identifier), 
                      index >= 0 && index < categoryLabels.count {
                // If identifier is a number, use it as index
                allConfidences[categoryLabels[index]] = observation.confidence
            }
        }
        
        // Get top category
        guard let topObservation = observations.first,
              topObservation.confidence >= confidenceThreshold else {
            return nil
        }
        
        // Determine the top category
        let topCategory: RaceCategory
        if let category = RaceCategory.fromLabel(topObservation.identifier) {
            topCategory = category
        } else if let index = Int(topObservation.identifier),
                  index >= 0 && index < categoryLabels.count {
            topCategory = categoryLabels[index]
        } else {
            // Default to highest confidence from our parsed results
            guard let bestMatch = allConfidences.max(by: { $0.value < $1.value }) else {
                return nil
            }
            topCategory = bestMatch.key
        }
        
        return ClassifiedFace(
            category: topCategory,
            confidence: topObservation.confidence,
            allConfidences: allConfidences
        )
    }
}

// MARK: - Errors

enum RaceClassificationError: LocalizedError {
    case modelNotFound
    case modelLoadFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Race classification model not found in bundle"
        case .modelLoadFailed(let error):
            return "Failed to load model: \(error.localizedDescription)"
        }
    }
}
