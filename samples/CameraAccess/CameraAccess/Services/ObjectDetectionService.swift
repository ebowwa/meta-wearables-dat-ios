/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// ObjectDetectionService.swift
//
// On-device object detection using YOLOv3 CoreML model.
// Processes video frames and returns detected objects with bounding boxes.
//

import Foundation
import Vision
import CoreML
import UIKit

/// Service for real-time object detection using YOLOv3
class ObjectDetectionService {
    
    static let shared = ObjectDetectionService()
    
    // MARK: - Properties
    
    private var model: VNCoreMLModel?
    private var isModelLoaded = false
    
    /// Minimum confidence threshold for detections
    var confidenceThreshold: Float = 0.5
    
    // MARK: - Initialization
    
    private init() {
        loadModel()
    }
    
    // MARK: - Model Loading
    
    private func loadModel() {
        do {
            // Load the YOLOv3Int8LUT model from bundle
            guard let modelURL = Bundle.main.url(forResource: "YOLOv3Int8LUT", withExtension: "mlmodelc") else {
                // Try loading uncompiled model
                guard let mlmodelURL = Bundle.main.url(forResource: "YOLOv3Int8LUT", withExtension: "mlmodel") else {
                    print("❌ YOLOv3 model not found in bundle")
                    return
                }
                let compiledURL = try MLModel.compileModel(at: mlmodelURL)
                let mlModel = try MLModel(contentsOf: compiledURL)
                model = try VNCoreMLModel(for: mlModel)
                isModelLoaded = true
                print("✅ YOLOv3 model compiled and loaded")
                return
            }
            
            let mlModel = try MLModel(contentsOf: modelURL)
            model = try VNCoreMLModel(for: mlModel)
            isModelLoaded = true
            print("✅ YOLOv3 model loaded successfully")
        } catch {
            print("❌ Failed to load YOLOv3 model: \(error)")
        }
    }
    
    // MARK: - Detection
    
    /// Detect objects in a UIImage
    /// - Parameter image: The image to analyze
    /// - Returns: Array of detected objects with bounding boxes
    func detectObjects(in image: UIImage) async -> [DetectedObject] {
        guard isModelLoaded, let model = model else {
            print("⚠️ Model not loaded")
            return []
        }
        
        guard let cgImage = image.cgImage else {
            return []
        }
        
        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { [weak self] request, error in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }
                
                if let error = error {
                    print("Detection error: \(error)")
                    continuation.resume(returning: [])
                    return
                }
                
                let detections = self.processResults(request.results)
                continuation.resume(returning: detections)
            }
            
            // Use scaleFill to maintain aspect ratio
            request.imageCropAndScaleOption = .scaleFill
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                print("Failed to perform detection: \(error)")
                continuation.resume(returning: [])
            }
        }
    }
    
    // MARK: - Processing Results
    
    private func processResults(_ results: [VNObservation]?) -> [DetectedObject] {
        guard let observations = results as? [VNRecognizedObjectObservation] else {
            return []
        }
        
        return observations
            .filter { $0.confidence >= confidenceThreshold }
            .compactMap { observation -> DetectedObject? in
                guard let topLabel = observation.labels.first else {
                    return nil
                }
                
                return DetectedObject(
                    label: topLabel.identifier,
                    confidence: observation.confidence,
                    boundingBox: observation.boundingBox
                )
            }
    }
}
