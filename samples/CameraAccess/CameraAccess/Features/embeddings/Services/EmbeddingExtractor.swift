//
//  EmbeddingExtractor.swift
//  CameraAccess
//
//  DEPRECATED: MobileNetV2 Embedding Extractor
//  This implementation has been disabled in favor of ResNet18 (matching Python reference).
//
//  ============================================================================
//  MOBILENETV2 EMBEDDING MODEL DOCUMENTATION
//  ============================================================================
//
//  MODEL: MobileNetEmbedding.mlpackage
//  ARCHITECTURE: MobileNetV2 (ImageNet pretrained)
//  OUTPUT DIMENSION: 1280-dimensional feature vector
//  INPUT SIZE: 224x224 RGB image
//
//  ORIGIN:
//  - Apple's CoreML Model Gallery: https://developer.apple.com/machine-learning/models/
//  - Or converted from TensorFlow/PyTorch using coremltools
//  - MobileNetV2 paper: https://arxiv.org/abs/1801.04381
//
//  HOW TO DOWNLOAD:
//  1. Visit https://developer.apple.com/machine-learning/models/
//  2. Download "MobileNetV2" or similar image classification model
//  3. Use coremltools to modify output to be the final pooling layer (1280-dim)
//     instead of the classification layer (1000-dim):
//
//     import coremltools as ct
//     model = ct.models.MLModel("MobileNetV2.mlmodel")
//     # Modify to output from GlobalAveragePooling layer
//     spec = model.get_spec()
//     # ... modify output layer ...
//     ct.models.utils.save_spec(spec, "MobileNetEmbedding.mlpackage")
//
//  LOCATION IN PROJECT:
//  CameraAccess/Features/embeddings/Models/MobileNetEmbedding.mlpackage
//
//  TO MOVE MODEL TO DESKTOP (remove from app):
//  Run in Terminal:
//    mv "/Users/ebowwa/apps/caringmind-project/com.mwdat-ios/samples/CameraAccess/CameraAccess/Features/embeddings/Models/MobileNetEmbedding.mlpackage" ~/Desktop/
//
//  WHY DEPRECATED:
//  - Python reference uses ResNet18 (512-dim), not MobileNetV2 (1280-dim)
//  - Different embedding spaces = different distance thresholds
//  - MobileNetV2 1280-dim suffers from "curse of dimensionality" for KNN
//  - ResNet18 features are better suited for few-shot similarity matching
//
//  TO RE-ENABLE:
//  1. Uncomment the implementation below
//  2. Remove the stub class at the bottom
//  3. Add MobileNetEmbedding.mlpackage back to the project
//
//  ============================================================================

/*
 * COMMENTED OUT MOBILENETV2 IMPLEMENTATION
 * =========================================
 
import Foundation
import CoreML
import Vision
import UIKit

/// Extracts 1280-dimensional embeddings from images using MobileNetV2
@MainActor
class EmbeddingExtractor: ObservableObject {
    
    private var model: VNCoreMLModel?
    private let embeddingDimension = 1280
    
    /// Indicates whether the model has been successfully loaded and is ready for inference
    @Published private(set) var isReady: Bool = false
    
    /// Error message if model loading failed
    @Published private(set) var loadError: String?
    
    /// Continuations waiting for the model to be ready
    private var waitingContinuations: [CheckedContinuation<Bool, Never>] = []
    
    /// Whether model loading has completed (successfully or with error)
    private var loadingCompleted: Bool = false
    
    init() {
        Task {
            await loadModel()
        }
    }
    
    /// Wait until the model is ready for inference
    /// - Returns: `true` if the model loaded successfully, `false` if loading failed
    func waitUntilReady() async -> Bool {
        // If already loaded, return immediately
        if loadingCompleted {
            return isReady
        }
        
        // Otherwise, wait for loading to complete
        return await withCheckedContinuation { continuation in
            waitingContinuations.append(continuation)
        }
    }
    
    private func loadModel() async {
        defer {
            // Mark loading as complete and notify all waiters
            loadingCompleted = true
            for continuation in waitingContinuations {
                continuation.resume(returning: isReady)
            }
            waitingContinuations.removeAll()
        }
        
        do {
            print("📦 Loading MobileNetEmbedding...")
            
            // First try to load pre-compiled model directly (Xcode may have compiled .mlpackage to .mlmodelc)
            if let compiledURL = Bundle.main.url(forResource: "MobileNetEmbedding", withExtension: "mlmodelc") {
                // Try loading directly without re-compilation
                do {
                    let mlModel = try MLModel(contentsOf: compiledURL)
                    model = try VNCoreMLModel(for: mlModel)
                    isReady = true
                    print("✅ MobileNetEmbedding loaded from pre-compiled model")
                    return
                } catch {
                    print("⚠️ Pre-compiled model failed, trying package: \(error.localizedDescription)")
                }
            }
            
            // Try loading from .mlpackage and compiling
            if let packageURL = Bundle.main.url(forResource: "MobileNetEmbedding", withExtension: "mlpackage") {
                let compiledURL = try await MLModel.compileModel(at: packageURL)
                let mlModel = try MLModel(contentsOf: compiledURL)
                model = try VNCoreMLModel(for: mlModel)
                isReady = true
                print("✅ MobileNetEmbedding loaded from package")
                return
            }
            
            loadError = "MobileNetEmbedding model not found in bundle"
            print("❌ \(loadError!)")
            
        } catch {
            loadError = error.localizedDescription
            print("❌ Failed to load MobileNetEmbedding: \(error)")
        }
    }
    
    /// Extract embedding from UIImage
    func extractEmbedding(from image: UIImage) async -> [Float]? {
        guard let cgImage = image.cgImage else { return nil }
        return await extractEmbedding(from: cgImage)
    }
    
    /// Extract embedding from CGImage
    func extractEmbedding(from cgImage: CGImage) async -> [Float]? {
        guard let model = model else {
            print("❌ Model not loaded")
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                if let error = error {
                    print("❌ Embedding extraction error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                      let multiArray = results.first?.featureValue.multiArrayValue else {
                    print("❌ No embedding results")
                    continuation.resume(returning: nil)
                    return
                }
                
                // Convert MLMultiArray to [Float]
                let embedding = self.multiArrayToFloats(multiArray)
                continuation.resume(returning: embedding)
            }
            
            request.imageCropAndScaleOption = .centerCrop
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("❌ Vision request error: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
    
    /// Extract embedding from CVPixelBuffer
    func extractEmbedding(from pixelBuffer: CVPixelBuffer) async -> [Float]? {
        guard let model = model else { return nil }
        
        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                      let multiArray = results.first?.featureValue.multiArrayValue else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let embedding = self.multiArrayToFloats(multiArray)
                continuation.resume(returning: embedding)
            }
            
            request.imageCropAndScaleOption = .centerCrop
            
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
    
    private func multiArrayToFloats(_ multiArray: MLMultiArray) -> [Float] {
        let count = multiArray.count
        var result = [Float](repeating: 0, count: count)
        
        let ptr = multiArray.dataPointer.assumingMemoryBound(to: Float.self)
        for i in 0..<count {
            result[i] = ptr[i]
        }
        
        // L2 normalize the embedding for cosine similarity (matches Python lines 133-137)
        // This is CRITICAL for cosine distance to work correctly
        return l2Normalize(result)
    }
    
    /// L2 normalize a vector (matches Python: embedding / np.linalg.norm(embedding))
    private func l2Normalize(_ vector: [Float]) -> [Float] {
        var squaredSum: Float = 0
        for v in vector {
            squaredSum += v * v
        }
        let norm = sqrt(squaredSum)
        
        guard norm > 0 else { return vector }
        
        return vector.map { $0 / norm }
    }
}

*/

// ============================================================================
// ResNet18 Embedding Extractor
// Matches Python: live-camera-learning/python/edaxshifu/knn_classifier.py
// ============================================================================

import Foundation
import CoreML
import Vision
import UIKit

/// Extracts 512-dimensional embeddings from images using ResNet18.
/// Matches Python reference: resnet18(weights='IMAGENET1K_V1') with final FC layer removed.
@MainActor
class EmbeddingExtractor: ObservableObject {
    
    private var model: VNCoreMLModel?
    private let embeddingDimension = 512  // ResNet18 outputs 512-dim (matches Python)
    
    /// Indicates whether the model has been successfully loaded and is ready for inference
    @Published private(set) var isReady: Bool = false
    
    /// Error message if model loading failed
    @Published private(set) var loadError: String?
    
    /// Continuations waiting for the model to be ready
    private var waitingContinuations: [CheckedContinuation<Bool, Never>] = []
    
    /// Whether model loading has completed (successfully or with error)
    private var loadingCompleted: Bool = false
    
    init() {
        Task {
            await loadModel()
        }
    }
    
    /// Wait until the model is ready for inference
    func waitUntilReady() async -> Bool {
        if loadingCompleted {
            return isReady
        }
        return await withCheckedContinuation { continuation in
            waitingContinuations.append(continuation)
        }
    }
    
    private func loadModel() async {
        defer {
            loadingCompleted = true
            for continuation in waitingContinuations {
                continuation.resume(returning: isReady)
            }
            waitingContinuations.removeAll()
        }
        
        // Try ResNet18 first (matches Python reference)
        if await tryLoadResNet18() {
            return
        }
        
        // Fallback to MobileNetV2 if ResNet18 not available
        print("⚠️ ResNet18 not available, trying MobileNetV2 fallback...")
        if await tryLoadMobileNet() {
            return
        }
        
        // List available models for debugging
        listAvailableModels()
        
        loadError = "No embedding model found in bundle (tried ResNet18 and MobileNetV2)"
        print("❌ \(loadError!)")
    }
    
    private func tryLoadResNet18() async -> Bool {
        print("📦 Loading ResNet18Embedding...")
        
        // Try pre-compiled model first
        if let compiledURL = Bundle.main.url(forResource: "ResNet18Embedding", withExtension: "mlmodelc") {
            do {
                let mlModel = try MLModel(contentsOf: compiledURL)
                model = try VNCoreMLModel(for: mlModel)
                isReady = true
                print("✅ ResNet18Embedding loaded from pre-compiled model (512-dim)")
                return true
            } catch {
                print("⚠️ Pre-compiled ResNet18 failed: \(error.localizedDescription)")
            }
        } else {
            print("📂 No ResNet18Embedding.mlmodelc found in bundle")
        }
        
        // Try .mlpackage
        if let packageURL = Bundle.main.url(forResource: "ResNet18Embedding", withExtension: "mlpackage") {
            do {
                let compiledURL = try await MLModel.compileModel(at: packageURL)
                let mlModel = try MLModel(contentsOf: compiledURL)
                model = try VNCoreMLModel(for: mlModel)
                isReady = true
                print("✅ ResNet18Embedding loaded from package (512-dim)")
                return true
            } catch {
                print("⚠️ ResNet18 package compile failed: \(error.localizedDescription)")
            }
        } else {
            print("📂 No ResNet18Embedding.mlpackage found in bundle")
        }
        
        return false
    }
    
    private func tryLoadMobileNet() async -> Bool {
        print("📦 Trying MobileNetEmbedding fallback...")
        
        // Try pre-compiled model first
        if let compiledURL = Bundle.main.url(forResource: "MobileNetEmbedding", withExtension: "mlmodelc") {
            do {
                let mlModel = try MLModel(contentsOf: compiledURL)
                model = try VNCoreMLModel(for: mlModel)
                isReady = true
                print("✅ MobileNetEmbedding loaded (1280-dim, fallback mode)")
                print("⚠️ Note: Using MobileNet 1280-dim instead of ResNet18 512-dim - different from Python reference")
                return true
            } catch {
                print("⚠️ Pre-compiled MobileNet failed: \(error.localizedDescription)")
            }
        }
        
        // Try .mlpackage
        if let packageURL = Bundle.main.url(forResource: "MobileNetEmbedding", withExtension: "mlpackage") {
            do {
                let compiledURL = try await MLModel.compileModel(at: packageURL)
                let mlModel = try MLModel(contentsOf: compiledURL)
                model = try VNCoreMLModel(for: mlModel)
                isReady = true
                print("✅ MobileNetEmbedding loaded from package (1280-dim, fallback mode)")
                return true
            } catch {
                print("⚠️ MobileNet package compile failed: \(error.localizedDescription)")
            }
        }
        
        return false
    }
    
    private func listAvailableModels() {
        print("🔍 Searching for ML models in bundle...")
        
        // Check for common model extensions
        let extensions = ["mlmodelc", "mlpackage", "mlmodel"]
        for ext in extensions {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                for url in urls {
                    print("   Found: \(url.lastPathComponent)")
                }
            }
        }
        
        // Also check subdirectories
        if let resourcePath = Bundle.main.resourcePath {
            let fileManager = FileManager.default
            if let enumerator = fileManager.enumerator(atPath: resourcePath) {
                while let element = enumerator.nextObject() as? String {
                    if element.contains(".mlpackage") || element.contains(".mlmodelc") {
                        print("   Found in subdir: \(element)")
                    }
                }
            }
        }
    }
    
    /// Extract embedding from UIImage
    func extractEmbedding(from image: UIImage) async -> [Float]? {
        guard let cgImage = image.cgImage else { return nil }
        return await extractEmbedding(from: cgImage)
    }
    
    /// Extract embedding from CGImage
    func extractEmbedding(from cgImage: CGImage) async -> [Float]? {
        guard let model = model else {
            print("❌ Model not loaded")
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                if let error = error {
                    print("❌ Embedding extraction error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                      let multiArray = results.first?.featureValue.multiArrayValue else {
                    print("❌ No embedding results")
                    continuation.resume(returning: nil)
                    return
                }
                
                let embedding = self.multiArrayToFloats(multiArray)
                continuation.resume(returning: embedding)
            }
            
            request.imageCropAndScaleOption = .centerCrop
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("❌ Vision request error: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
    
    /// Extract embedding from CVPixelBuffer
    func extractEmbedding(from pixelBuffer: CVPixelBuffer) async -> [Float]? {
        guard let model = model else { return nil }
        
        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                      let multiArray = results.first?.featureValue.multiArrayValue else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let embedding = self.multiArrayToFloats(multiArray)
                continuation.resume(returning: embedding)
            }
            
            request.imageCropAndScaleOption = .centerCrop
            
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
    
    private func multiArrayToFloats(_ multiArray: MLMultiArray) -> [Float] {
        let count = multiArray.count
        var result = [Float](repeating: 0, count: count)
        
        let ptr = multiArray.dataPointer.assumingMemoryBound(to: Float.self)
        for i in 0..<count {
            result[i] = ptr[i]
        }
        
        // L2 normalize the embedding for cosine similarity (matches Python lines 133-137)
        return l2Normalize(result)
    }
    
    /// L2 normalize a vector (matches Python: embedding / np.linalg.norm(embedding))
    private func l2Normalize(_ vector: [Float]) -> [Float] {
        var squaredSum: Float = 0
        for v in vector {
            squaredSum += v * v
        }
        let norm = sqrt(squaredSum)
        
        guard norm > 0 else { return vector }
        
        return vector.map { $0 / norm }
    }
}

