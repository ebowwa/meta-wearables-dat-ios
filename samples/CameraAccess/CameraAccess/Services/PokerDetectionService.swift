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

/// Service for real-time poker card detection using YOLO11 CoreML model
@MainActor
class PokerDetectionService {
    
    static let shared = PokerDetectionService()
    
    /// Minimum confidence threshold for detections (0-1)
    var confidenceThreshold: Float = 0.5
    
    /// Whether the service is ready to perform detections
    private(set) var isReady = false
    
    /// Error from loading the model, if any
    private(set) var loadError: Error?
    
    private var model: VNCoreMLModel?
    
    private init() {
        Task {
            await loadModel()
        }
    }
    
    /// Load the YOLO11 poker detection model
    func loadModel() async {
        do {
            // Try to load the mlmodelc (compiled) or mlpackage from the app bundle
            var modelURL: URL? = Bundle.main.url(forResource: "YOLO11PokerInt8LUT", withExtension: "mlmodelc")
            if modelURL != nil {
                print("📦 Found compiled model: YOLO11PokerInt8LUT.mlmodelc")
            } else {
                modelURL = Bundle.main.url(forResource: "YOLO11PokerInt8LUT", withExtension: "mlpackage")
                if modelURL != nil {
                    print("📦 Found mlpackage: YOLO11PokerInt8LUT.mlpackage")
                }
            }
            
            guard let url = modelURL else {
                print("❌ Model not found in bundle. Available resources:")
                if let resourcePath = Bundle.main.resourcePath {
                    let fm = FileManager.default
                    let items = try? fm.contentsOfDirectory(atPath: resourcePath)
                    items?.forEach { print("   - \($0)") }
                }
                throw PokerDetectionError.modelNotFound
            }
            
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine  // Optimize for on-device ML
            
            print("⏳ Loading model from: \(url.lastPathComponent)...")
            let mlModel = try await MLModel.load(contentsOf: url, configuration: config)
            
            print("📊 Model description: \(mlModel.modelDescription.predictedFeatureName ?? "N/A")")
            print("📊 Inputs: \(mlModel.modelDescription.inputDescriptionsByName.keys.joined(separator: ", "))")
            print("📊 Outputs: \(mlModel.modelDescription.outputDescriptionsByName.keys.joined(separator: ", "))")
            
            self.model = try VNCoreMLModel(for: mlModel)
            self.isReady = true
            self.loadError = nil
            
            print("✅ YOLO11 Poker Detection model loaded successfully")
        } catch {
            self.loadError = error
            self.isReady = false
            print("❌ Failed to load YOLO11 model: \(error)")
        }
    }
    
    /// Detect poker cards in the given image
    /// - Parameter image: UIImage from video frame
    /// - Returns: Array of detected cards with confidence and bounding boxes
    func detect(image: UIImage) async -> [DetectedCard] {
        guard isReady, let model = model else {
            return []
        }
        
        guard let cgImage = image.cgImage else {
            return []
        }
        
        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                if let error = error {
                    print("❌ Vision request error: \(error)")
                    continuation.resume(returning: [])
                    return
                }
                
                // Log all observation types for debugging
                if let allResults = request.results, !allResults.isEmpty {
                    print("📊 Vision returned \(allResults.count) results of type: \(type(of: allResults.first!))")
                } else {
                    print("⚠️ Vision returned 0 results")
                }
                
                guard let results = request.results as? [VNRecognizedObjectObservation] else {
                    // Handle raw YOLO output using custom decoder
                    if let featureResults = request.results as? [VNCoreMLFeatureValueObservation],
                       let firstFeature = featureResults.first {
                        let decodedCards = YOLOOutputDecoder.shared.decode(featureValue: firstFeature.featureValue)
                        continuation.resume(returning: decodedCards)
                        return
                    }
                    continuation.resume(returning: [])
                    return
                }
                
                let detectedCards = results.compactMap { observation -> DetectedCard? in
                    guard observation.confidence >= self.confidenceThreshold else {
                        return nil
                    }
                    
                    // Get the top classification label
                    guard let topLabel = observation.labels.first else {
                        return nil
                    }
                    
                    // Parse the YOLO label (e.g., "10c", "Ah", "Ks")
                    guard let card = PokerCard.fromYOLOLabel(topLabel.identifier) else {
                        return nil
                    }
                    
                    print("🔍 Detected: \(card.displayName) (\(Int(observation.confidence * 100))%)")
                    
                    // Convert Vision coordinates (bottom-left origin) to UIKit (top-left origin)
                    let boundingBox = observation.boundingBox
                    let normalizedBox = CGRect(
                        x: boundingBox.origin.x,
                        y: 1 - boundingBox.origin.y - boundingBox.height,
                        width: boundingBox.width,
                        height: boundingBox.height
                    )
                    
                    return DetectedCard(
                        card: card,
                        confidence: observation.confidence,
                        boundingBox: normalizedBox
                    )
                }
                
                continuation.resume(returning: detectedCards)
            }
            
            // Configure for YOLO-style detection
            request.imageCropAndScaleOption = .scaleFill
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("Vision request failed: \(error)")
                continuation.resume(returning: [])
            }
        }
    }
}

// MARK: - Errors

enum PokerDetectionError: LocalizedError {
    case modelNotFound
    case modelLoadFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "YOLO11 poker detection model not found in bundle"
        case .modelLoadFailed(let error):
            return "Failed to load model: \(error.localizedDescription)"
        }
    }
}
