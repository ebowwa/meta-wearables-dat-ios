//
//  EmbeddingExtractor.swift
//  CameraAccess
//
//  Extracts feature embeddings from images using MobileNetV2
//

import Foundation
import CoreML
import Vision
import UIKit

/// Extracts 1280-dimensional embeddings from images using MobileNetV2
@MainActor
class EmbeddingExtractor {
    
    private var model: VNCoreMLModel?
    private let embeddingDimension = 1280
    
    init() {
        Task {
            await loadModel()
        }
    }
    
    private func loadModel() async {
        do {
            print("📦 Loading MobileNetEmbedding...")
            
            // First try to load pre-compiled model directly (Xcode may have compiled .mlpackage to .mlmodelc)
            if let compiledURL = Bundle.main.url(forResource: "MobileNetEmbedding", withExtension: "mlmodelc") {
                // Try loading directly without re-compilation
                do {
                    let mlModel = try MLModel(contentsOf: compiledURL)
                    model = try VNCoreMLModel(for: mlModel)
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
                print("✅ MobileNetEmbedding loaded from package")
                return
            }
            
            print("❌ MobileNetEmbedding model not found in bundle")
            
        } catch {
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
        
        return result
    }
}
