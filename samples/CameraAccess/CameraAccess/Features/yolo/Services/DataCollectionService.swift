//
//  DataCollectionService.swift
//  CameraAccess
//
//  Captures frames with YOLO annotations for dataset creation
//

import Foundation
import UIKit
import CoreML
import Vision

/// Represents a captured frame with its detections
struct CapturedFrame {
    let image: UIImage
    let timestamp: Date
    let detections: [Detection]
    
    struct Detection {
        let classId: Int
        let className: String
        let confidence: Float
        let boundingBox: CGRect // Normalized 0-1
    }
}

/// Service for collecting training data from glasses stream
@MainActor
class DataCollectionService: ObservableObject {
    
    // MARK: - Published State
    @Published var isCapturing = false
    @Published var capturedCount = 0
    @Published var lastCapture: CapturedFrame?
    @Published var autoCapture = false
    @Published var autoCaptureCooldown: TimeInterval = 2.0 // seconds between auto-captures
    
    // MARK: - YOLO Detection
    private var model: VNCoreMLModel?
    private var lastAutoCaptureTime = Date.distantPast
    
    // MARK: - Storage
    private let datasetPath: URL
    private let imagesPath: URL
    private let labelsPath: URL
    
    // COCO class names (80 classes)
    let classNames = [
        "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
        "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat",
        "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack",
        "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball",
        "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket",
        "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
        "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake",
        "chair", "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop",
        "mouse", "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink",
        "refrigerator", "book", "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush"
    ]
    
    init() {
        // Set up dataset directories
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        datasetPath = documentsPath.appendingPathComponent("YOLODataset")
        imagesPath = datasetPath.appendingPathComponent("images")
        labelsPath = datasetPath.appendingPathComponent("labels")
        
        setupDirectories()
        loadModel()
    }
    
    private func setupDirectories() {
        try? FileManager.default.createDirectory(at: imagesPath, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: labelsPath, withIntermediateDirectories: true)
        
        // Save classes.txt
        let classesFile = datasetPath.appendingPathComponent("classes.txt")
        let classesContent = classNames.joined(separator: "\n")
        try? classesContent.write(to: classesFile, atomically: true, encoding: .utf8)
        
        print("📁 Dataset directory: \(datasetPath.path)")
    }
    
    private func loadModel() {
        Task {
            do {
                // Try to load base YOLO11n
                guard let modelURL = Bundle.main.url(forResource: "yolo11n", withExtension: "mlmodelc")
                    ?? Bundle.main.url(forResource: "yolo11n", withExtension: "mlpackage") else {
                    print("❌ Base YOLO model not found")
                    return
                }
                
                print("📦 Loading base YOLO: \(modelURL.lastPathComponent)")
                let compiledURL = try await MLModel.compileModel(at: modelURL)
                let mlModel = try MLModel(contentsOf: compiledURL)
                model = try VNCoreMLModel(for: mlModel)
                print("✅ Base YOLO loaded - 80 COCO classes")
                
            } catch {
                print("❌ Failed to load YOLO: \(error)")
            }
        }
    }
    
    // MARK: - Detection
    
    /// Process a frame and return detections
    func detect(pixelBuffer: CVPixelBuffer) async -> [CapturedFrame.Detection] {
        guard let model = model else { return [] }
        
        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                      let multiArray = results.first?.featureValue.multiArrayValue else {
                    continuation.resume(returning: [])
                    return
                }
                
                let detections = self.decodeYOLO(multiArray: multiArray)
                continuation.resume(returning: detections)
            }
            
            request.imageCropAndScaleOption = .scaleFill
            
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("❌ Vision error: \(error)")
                continuation.resume(returning: [])
            }
        }
    }
    
    /// Decode YOLO output tensor
    private func decodeYOLO(multiArray: MLMultiArray) -> [CapturedFrame.Detection] {
        let shape = multiArray.shape.map { $0.intValue }
        guard shape.count == 3 else { return [] }
        
        let numFeatures = shape[1] // 84 for COCO (4 box + 80 classes)
        let numPredictions = shape[2] // 8400
        let numClasses = numFeatures - 4
        
        var detections: [CapturedFrame.Detection] = []
        let confidenceThreshold: Float = 0.25
        
        let pointer = multiArray.dataPointer.assumingMemoryBound(to: Float.self)
        
        for i in 0..<numPredictions {
            // Find best class
            var maxConf: Float = 0
            var maxClass = 0
            
            for c in 0..<numClasses {
                let conf = pointer[(4 + c) * numPredictions + i]
                if conf > maxConf {
                    maxConf = conf
                    maxClass = c
                }
            }
            
            guard maxConf >= confidenceThreshold else { continue }
            
            // Get bounding box (center x, center y, width, height)
            let cx = pointer[0 * numPredictions + i]
            let cy = pointer[1 * numPredictions + i]
            let w = pointer[2 * numPredictions + i]
            let h = pointer[3 * numPredictions + i]
            
            // Convert to normalized rect
            let x = (cx - w / 2) / 640.0
            let y = (cy - h / 2) / 640.0
            let width = w / 640.0
            let height = h / 640.0
            
            let className = maxClass < classNames.count ? classNames[maxClass] : "unknown"
            
            detections.append(CapturedFrame.Detection(
                classId: maxClass,
                className: className,
                confidence: maxConf,
                boundingBox: CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
            ))
        }
        
        // Simple NMS
        return nonMaxSuppression(detections: detections, iouThreshold: 0.45)
    }
    
    private func nonMaxSuppression(detections: [CapturedFrame.Detection], iouThreshold: Float) -> [CapturedFrame.Detection] {
        let sorted = detections.sorted { $0.confidence > $1.confidence }
        var kept: [CapturedFrame.Detection] = []
        
        for detection in sorted {
            var dominated = false
            for existing in kept {
                if iou(detection.boundingBox, existing.boundingBox) > iouThreshold {
                    dominated = true
                    break
                }
            }
            if !dominated {
                kept.append(detection)
            }
        }
        
        return kept
    }
    
    private func iou(_ a: CGRect, _ b: CGRect) -> Float {
        let intersection = a.intersection(b)
        if intersection.isNull { return 0 }
        let union = a.union(b)
        return Float(intersection.width * intersection.height) / Float(union.width * union.height)
    }
    
    // MARK: - Capture
    
    /// Manually capture current frame
    func captureFrame(image: UIImage, detections: [CapturedFrame.Detection]) {
        let frame = CapturedFrame(image: image, timestamp: Date(), detections: detections)
        saveFrame(frame)
        lastCapture = frame
        capturedCount += 1
    }
    
    /// Check if auto-capture should trigger
    func shouldAutoCapture(detections: [CapturedFrame.Detection]) -> Bool {
        guard autoCapture, !detections.isEmpty else { return false }
        
        let now = Date()
        if now.timeIntervalSince(lastAutoCaptureTime) >= autoCaptureCooldown {
            lastAutoCaptureTime = now
            return true
        }
        return false
    }
    
    /// Save frame to dataset
    private func saveFrame(_ frame: CapturedFrame) {
        let filename = "frame_\(Int(frame.timestamp.timeIntervalSince1970 * 1000))"
        
        // Save image
        let imagePath = imagesPath.appendingPathComponent("\(filename).jpg")
        if let jpegData = frame.image.jpegData(compressionQuality: 0.9) {
            try? jpegData.write(to: imagePath)
        }
        
        // Save labels (YOLO format: class_id center_x center_y width height)
        let labelPath = labelsPath.appendingPathComponent("\(filename).txt")
        var labelContent = ""
        for detection in frame.detections {
            let cx = detection.boundingBox.midX
            let cy = detection.boundingBox.midY
            let w = detection.boundingBox.width
            let h = detection.boundingBox.height
            labelContent += "\(detection.classId) \(cx) \(cy) \(w) \(h)\n"
        }
        try? labelContent.write(to: labelPath, atomically: true, encoding: .utf8)
        
        print("💾 Saved: \(filename) with \(frame.detections.count) detections")
    }
    
    // MARK: - Dataset Management
    
    /// Get dataset statistics
    func getDatasetStats() -> (imageCount: Int, totalDetections: Int) {
        let fm = FileManager.default
        let images = (try? fm.contentsOfDirectory(atPath: imagesPath.path))?.count ?? 0
        
        var totalDetections = 0
        if let labels = try? fm.contentsOfDirectory(atPath: labelsPath.path) {
            for label in labels where label.hasSuffix(".txt") {
                let path = labelsPath.appendingPathComponent(label)
                if let content = try? String(contentsOf: path, encoding: .utf8) {
                    totalDetections += content.components(separatedBy: "\n").filter { !$0.isEmpty }.count
                }
            }
        }
        
        return (images, totalDetections)
    }
    
    /// Clear all captured data
    func clearDataset() {
        try? FileManager.default.removeItem(at: imagesPath)
        try? FileManager.default.removeItem(at: labelsPath)
        setupDirectories()
        capturedCount = 0
        print("🗑️ Dataset cleared")
    }
    
    /// Get dataset path for export
    func getDatasetPath() -> URL {
        return datasetPath
    }
}
