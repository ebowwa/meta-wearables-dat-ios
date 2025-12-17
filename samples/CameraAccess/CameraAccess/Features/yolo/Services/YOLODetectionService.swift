/*
 * YOLODetectionService.swift
 * CameraAccess
 *
 * Generic YOLO detection service that works with any loaded VNCoreMLModel.
 * Supports YOLOv3, YOLOv8, YOLOv10, YOLO11 and other compatible models.
 */

import Foundation
@preconcurrency import Vision
import UIKit

/// A detected object from YOLO inference
struct YOLODetection: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let confidence: Float
    let boundingBox: CGRect  // Normalized coordinates (0-1)
    
    /// Get bounding box in view coordinates
    func boundingBox(in viewSize: CGSize) -> CGRect {
        // Vision uses bottom-left origin, convert to top-left
        let x = boundingBox.origin.x * viewSize.width
        let y = (1 - boundingBox.origin.y - boundingBox.height) * viewSize.height
        let width = boundingBox.width * viewSize.width
        let height = boundingBox.height * viewSize.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Generic YOLO detection service
@MainActor
class YOLODetectionService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var isProcessing = false
    @Published private(set) var lastDetections: [YOLODetection] = []
    @Published private(set) var interpretedResult: InterpretedDetections?
    @Published private(set) var inferenceTimeMs: Double = 0
    @Published var confidenceThreshold: Float = 0.5
    @Published var isEnabled = false
    
    // MARK: - Private Properties
    
    private var visionModel: VNCoreMLModel?
    private var currentModelType: YOLOModelType = .generic
    private var lastProcessTime: Date?
    private let minProcessingInterval: TimeInterval = 0.05  // 20 FPS max
    
    // MARK: - Model Management
    
    /// Update the model used for detection
    func setModel(_ model: VNCoreMLModel?, modelType: YOLOModelType = .generic) {
        self.visionModel = model
        self.currentModelType = modelType
        self.lastDetections = []
        self.interpretedResult = nil
    }
    
    var hasModel: Bool {
        visionModel != nil
    }
    
    var modelType: YOLOModelType {
        currentModelType
    }
    
    // MARK: - Detection
    
    /// Run detection on an image
    func detect(in image: UIImage) async -> [YOLODetection] {
        guard isEnabled,
              let visionModel = visionModel,
              let cgImage = image.cgImage else {
            return []
        }
        
        // Throttle processing
        if let lastTime = lastProcessTime,
           Date().timeIntervalSince(lastTime) < minProcessingInterval {
            return lastDetections
        }
        
        isProcessing = true
        let startTime = Date()
        let threshold = confidenceThreshold
        
        // Perform detection on background thread
        let detections: [YOLODetection] = await withCheckedContinuation { continuation in
            Task.detached {
                let request = VNCoreMLRequest(model: visionModel) { request, error in
                    if let error = error {
                        print("YOLO Detection error: \(error)")
                        continuation.resume(returning: [])
                        return
                    }
                    
                    let results = Self.processResults(request.results, threshold: threshold)
                    continuation.resume(returning: results)
                }
                
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
        
        let endTime = Date()
        inferenceTimeMs = endTime.timeIntervalSince(startTime) * 1000
        lastProcessTime = endTime
        lastDetections = detections
        
        // Run interpreter for model-specific processing
        let interpreter = InterpreterRegistry.shared.interpreter(for: currentModelType)
        interpretedResult = interpreter.interpret(detections)
        
        isProcessing = false
        
        return detections
    }
    
    // Made static and nonisolated to avoid MainActor isolation issues
    private nonisolated static func processResults(_ results: [Any]?, threshold: Float) -> [YOLODetection] {
        guard let observations = results as? [VNRecognizedObjectObservation] else {
            return []
        }
        
        return observations.compactMap { observation in
            guard let topLabel = observation.labels.first,
                  topLabel.confidence >= threshold else {
                return nil
            }
            
            return YOLODetection(
                label: topLabel.identifier,
                confidence: topLabel.confidence,
                boundingBox: observation.boundingBox
            )
        }
    }
}

