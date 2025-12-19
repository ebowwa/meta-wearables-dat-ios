//
//  TrainingService.swift
//  CameraAccess
//
//  Orchestrates on-device training and inference using embeddings + KNN
//

import Foundation
import UIKit
import Combine

/// Training modes for the data collection system
enum TrainingMode {
    case inference  // Predict labels
    case training   // Collect samples
}

/// Service that combines embedding extraction with KNN for on-device learning
@MainActor
class TrainingService: ObservableObject {
    
    // MARK: - Dependencies
    private let embeddingExtractor = EmbeddingExtractor()
    let knn = OnDeviceKNN()
    
    // MARK: - Published State
    @Published var mode: TrainingMode = .training
    @Published var currentLabel: String = ""
    @Published var lastPrediction: KNNResult?
    @Published var isProcessing = false
    
    // MARK: - Statistics
    @Published var trainingSamples: Int = 0
    @Published var trainedClasses: [String] = []
    
    init() {
        updateStats()
    }
    
    // MARK: - Training
    
    /// Add a training sample from image
    func addTrainingSample(image: UIImage, label: String) async -> Bool {
        guard !label.isEmpty else {
            print("❌ Cannot add sample with empty label")
            return false
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        guard let embedding = await embeddingExtractor.extractEmbedding(from: image) else {
            print("❌ Failed to extract embedding")
            return false
        }
        
        knn.addSample(embedding: embedding, label: label)
        knn.saveModel()
        updateStats()
        
        print("✅ Added training sample for '\(label)'")
        return true
    }
    
    /// Add training sample from CVPixelBuffer
    func addTrainingSample(pixelBuffer: CVPixelBuffer, label: String) async -> Bool {
        guard !label.isEmpty else { return false }
        
        isProcessing = true
        defer { isProcessing = false }
        
        guard let embedding = await embeddingExtractor.extractEmbedding(from: pixelBuffer) else {
            return false
        }
        
        knn.addSample(embedding: embedding, label: label)
        knn.saveModel()
        updateStats()
        return true
    }
    
    /// Add training sample from CGImage (avoids UIImage conversion overhead)
    func addTrainingSample(cgImage: CGImage, label: String) async -> Bool {
        guard !label.isEmpty else { return false }
        
        isProcessing = true
        defer { isProcessing = false }
        
        guard let embedding = await embeddingExtractor.extractEmbedding(from: cgImage) else {
            return false
        }
        
        knn.addSample(embedding: embedding, label: label)
        knn.saveModel()
        updateStats()
        return true
    }
    
    /// Add training sample from a cropped detection region
    /// - Parameters:
    ///   - image: The full frame image
    ///   - boundingBox: Normalized bounding box (0-1 coordinates, Vision-style with bottom-left origin)
    ///   - label: The label for this object
    func addTrainingSample(image: UIImage, boundingBox: CGRect, label: String) async -> Bool {
        guard !label.isEmpty else {
            print("❌ Cannot add sample with empty label")
            return false
        }
        
        guard let croppedImage = cropImage(image, to: boundingBox) else {
            print("❌ Failed to crop image to bounding box")
            return false
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        guard let embedding = await embeddingExtractor.extractEmbedding(from: croppedImage) else {
            print("❌ Failed to extract embedding from cropped region")
            return false
        }
        
        knn.addSample(embedding: embedding, label: label)
        knn.saveModel()
        updateStats()
        
        print("✅ Added training sample for '\(label)' from cropped detection")
        return true
    }
    
    /// Crop an image to a normalized bounding box (Vision-style coordinates)
    private func cropImage(_ image: UIImage, to normalizedBox: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        
        // Convert normalized coordinates to pixel coordinates
        // Vision uses bottom-left origin, so we flip the Y coordinate
        let x = normalizedBox.origin.x * imageWidth
        let y = (1 - normalizedBox.origin.y - normalizedBox.height) * imageHeight
        let width = normalizedBox.width * imageWidth
        let height = normalizedBox.height * imageHeight
        
        // Clamp to image bounds
        let cropRect = CGRect(
            x: max(0, x),
            y: max(0, y),
            width: min(width, imageWidth - x),
            height: min(height, imageHeight - y)
        )
        
        // Ensure we have a valid crop rect
        guard cropRect.width > 0 && cropRect.height > 0 else {
            print("❌ Invalid crop rect: \(cropRect)")
            return nil
        }
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            print("❌ CGImage cropping failed")
            return nil
        }
        
        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    // MARK: - Inference
    
    /// Predict label for image
    func predict(image: UIImage) async -> KNNResult? {
        isProcessing = true
        defer { isProcessing = false }
        
        guard let embedding = await embeddingExtractor.extractEmbedding(from: image) else {
            return nil
        }
        
        let result = knn.predict(embedding: embedding)
        lastPrediction = result
        return result
    }
    
    /// Predict label for CVPixelBuffer
    func predict(pixelBuffer: CVPixelBuffer) async -> KNNResult? {
        guard let embedding = await embeddingExtractor.extractEmbedding(from: pixelBuffer) else {
            return nil
        }
        
        let result = knn.predict(embedding: embedding)
        lastPrediction = result
        return result
    }
    
    // MARK: - Data Management
    
    /// Remove all samples for a specific label
    func removeSamples(for label: String) {
        knn.removeSamples(for: label)
        knn.saveModel()
        updateStats()
    }
    
    /// Reset all training data
    func resetModel() {
        knn.reset()
        knn.saveModel()
        updateStats()
        lastPrediction = nil
    }
    
    /// Reload model from storage
    func reloadModel() {
        knn.loadModel()
        updateStats()
    }
    
    private func updateStats() {
        trainingSamples = knn.totalSamples
        trainedClasses = knn.trainedClasses
    }
    
    // MARK: - Export/Import
    
    /// Get model storage path
    func getModelPath() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("knn_model.json")
    }
    
    /// Export statistics
    func getStats() -> [String: Any] {
        return [
            "totalSamples": trainingSamples,
            "trainedClasses": trainedClasses,
            "samplesPerClass": knn.samplesPerClass,
            "k": knn.k,
            "confidenceThreshold": knn.confidenceThreshold
        ]
    }
}
