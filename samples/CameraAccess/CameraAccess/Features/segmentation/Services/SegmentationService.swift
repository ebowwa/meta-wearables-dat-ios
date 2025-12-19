/*
 * SegmentationService.swift
 * CameraAccess
 *
 * Service for semantic segmentation using MobileViT + DeepLabV3.
 * Outputs per-pixel class predictions for 21 PASCAL VOC classes.
 *
 * ============================================================================
 * HOW THE VIT (VISION TRANSFORMER) SEGMENTATION WAS ADDED AND WORKS:
 * ============================================================================
 *
 * ARCHITECTURE OVERVIEW:
 * ----------------------
 * MobileViT is a hybrid architecture combining CNNs and Vision Transformers.
 * It replaces local processing in CNNs with global processing via transformers.
 * DeepLabV3 decoder head is added for dense per-pixel predictions.
 *
 * MODEL INTEGRATION:
 * ------------------
 * 1. The model file "DeepLabV3MobileViT.mlpackage" or ".mlmodelc" is bundled
 *    in the app. It was converted from PyTorch using coremltools.
 *
 * 2. loadModel() asynchronously:
 *    - Searches Bundle for the model file (.mlmodelc preferred, falls back to .mlpackage)
 *    - Compiles the model using MLModel.compileModel(at:) for optimized inference
 *    - Wraps it in VNCoreMLModel for Vision framework integration
 *
 * INPUT/OUTPUT SPECIFICATION:
 * ---------------------------
 * - Input: 512x512 RGB image (Vision auto-scales via .scaleFill)
 * - Output: MLMultiArray with shape [1, 21, H, W] or [21, H, W]
 *   - 21 channels = PASCAL VOC classes (background, person, car, etc.)
 *   - Each pixel has 21 logit scores; argmax gives predicted class
 *
 * INFERENCE FLOW:
 * ---------------
 * 1. segment(image:) receives UIImage from camera/glasses stream
 * 2. Throttled to 10 FPS (minInterval = 0.1s) to prevent overload
 * 3. VNCoreMLRequest processes CGImage through the model
 * 4. decode(multiArray:) extracts per-pixel class predictions:
 *    - Iterates over H x W pixels
 *    - For each pixel, finds class with max logit across 21 channels
 *    - Returns 2D mask of class IDs
 *
 * RESULT STRUCTURE:
 * -----------------
 * SegmentationResult contains:
 * - mask: 2D array of class IDs (0-20) matching output resolution
 * - originalSize: source image dimensions for overlay scaling
 * - processingTimeMs: inference latency for performance monitoring
 * - detectedClasses: computed property listing non-background classes found
 *
 * UI INTEGRATION:
 * ---------------
 * - hasModel: published bool for UI to show/hide segmentation toggle
 * - isEnabled: user toggle to activate/deactivate real-time segmentation
 * - lastResult: published for SwiftUI overlay views to render color masks
 *
 * COLOR CODING:
 * -------------
 * SegmentationClass enum maps each class to a semi-transparent color:
 * - Person: Green, Car: Blue, Cat: Orange, Dog: Pink
 * - Background is clear (no overlay)
 *
 * ============================================================================
 */

import Foundation
import CoreML
import Vision
import UIKit

// MARK: - ViT Segmentation Implementation (Currently Disabled)
// The following code implements MobileViT + DeepLabV3 semantic segmentation.
// Uncomment to enable real-time per-pixel classification of 21 PASCAL VOC classes.

/*
/// PASCAL VOC 21 semantic segmentation classes
enum SegmentationClass: Int, CaseIterable {
    case background = 0, aeroplane, bicycle, bird, boat, bottle
    case bus, car, cat, chair, cow, diningTable, dog
    case horse, motorbike, person, pottedPlant, sheep, sofa
    case train, tvMonitor
    
    var displayName: String {
        switch self {
        case .background: return "Background"
        case .person: return "Person"
        case .car: return "Car"
        case .cat: return "Cat"
        case .dog: return "Dog"
        case .chair: return "Chair"
        case .bottle: return "Bottle"
        case .tvMonitor: return "TV/Monitor"
        default: return String(describing: self).capitalized
        }
    }
    
    var color: UIColor {
        switch self {
        case .background: return .clear
        case .person: return UIColor(red: 0, green: 1, blue: 0, alpha: 0.6)
        case .car: return UIColor(red: 0, green: 0, blue: 1, alpha: 0.6)
        case .cat: return UIColor(red: 1, green: 0.5, blue: 0, alpha: 0.6)
        case .dog: return UIColor(red: 1, green: 0, blue: 0.5, alpha: 0.6)
        default: return UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.5)
        }
    }
}

/// Result of semantic segmentation
/// - mask: 2D array where each element is a class ID (0-20)
/// - originalSize: dimensions of source image for overlay scaling
/// - processingTimeMs: inference time for performance metrics
struct SegmentationResult {
    let mask: [[Int]]  // 2D array of class IDs
    let originalSize: CGSize
    let processingTimeMs: Double
    
    /// Returns all non-background classes detected in the mask
    var detectedClasses: [SegmentationClass] {
        var classSet = Set<Int>()
        for row in mask {
            for classId in row where classId != 0 {
                classSet.insert(classId)
            }
        }
        return classSet.compactMap { SegmentationClass(rawValue: $0) }
    }
}

/// Service for MobileViT + DeepLabV3 semantic segmentation
/// 
/// Usage:
/// 1. Call loadModel() on app launch to initialize the CoreML model
/// 2. Set isEnabled = true to activate segmentation
/// 3. Call segment(image:) for each camera frame
/// 4. Observe lastResult to render segmentation overlay
@MainActor
class SegmentationService: ObservableObject {
    /// User toggle for enabling/disabling segmentation
    @Published var isEnabled = false
    
    /// Most recent segmentation result for UI binding
    @Published var lastResult: SegmentationResult?
    
    /// True once model is successfully loaded
    @Published var hasModel = false
    
    /// VNCoreMLModel wrapper for Vision framework inference
    private var model: VNCoreMLModel?
    
    /// Timestamp of last processed frame for throttling
    private var lastProcessTime = Date.distantPast
    
    /// Minimum interval between frames (0.1s = 10 FPS max)
    private let minInterval: TimeInterval = 0.1
    
    /// Loads the DeepLabV3MobileViT model from app bundle
    /// - Searches for .mlmodelc first (pre-compiled), then .mlpackage
    /// - Compiles model for current device if needed
    /// - Wraps in VNCoreMLModel for Vision integration
    func loadModel() async {
        // Look for compiled model first, then source package
        guard let url = Bundle.main.url(forResource: "DeepLabV3MobileViT", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "DeepLabV3MobileViT", withExtension: "mlpackage") else {
            print("❌ DeepLabV3MobileViT not found")
            return
        }
        do {
            // Compile model for current device (returns cached path if already compiled)
            let compiled = try await MLModel.compileModel(at: url)
            let mlModel = try MLModel(contentsOf: compiled)
            
            // Wrap for Vision framework to handle image preprocessing
            model = try VNCoreMLModel(for: mlModel)
            hasModel = true
            print("✅ DeepLabV3MobileViT loaded")
        } catch {
            print("❌ Failed to load: \(error)")
        }
    }
    
    /// Performs semantic segmentation on an image
    /// - Parameter image: Source image from camera or glasses stream
    /// - Returns: SegmentationResult with per-pixel class mask, or nil if disabled/throttled
    func segment(image: UIImage) async -> SegmentationResult? {
        guard let model = model, isEnabled else { return nil }
        
        // Throttle to prevent processing every frame (10 FPS max)
        let now = Date()
        guard now.timeIntervalSince(lastProcessTime) >= minInterval else { return lastResult }
        lastProcessTime = now
        
        let start = CFAbsoluteTimeGetCurrent()
        guard let cgImage = image.cgImage else { return nil }
        
        return await withCheckedContinuation { continuation in
            // Create Vision request with CoreML model
            let request = VNCoreMLRequest(model: model) { req, _ in
                // Extract MLMultiArray from Vision results
                guard let results = req.results as? [VNCoreMLFeatureValueObservation],
                      let arr = results.first?.featureValue.multiArrayValue else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Decode multiarray to 2D class mask
                let mask = self.decode(multiArray: arr)
                let result = SegmentationResult(
                    mask: mask,
                    originalSize: CGSize(width: cgImage.width, height: cgImage.height),
                    processingTimeMs: (CFAbsoluteTimeGetCurrent() - start) * 1000
                )
                
                // Update published property on main actor
                Task { @MainActor in self.lastResult = result }
                continuation.resume(returning: result)
            }
            
            // Scale image to model input size (512x512) filling entire area
            request.imageCropAndScaleOption = .scaleFill
            
            // Run inference
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
    
    /// Decodes MLMultiArray output to 2D class mask
    /// - Parameter multiArray: Model output with shape [1,21,H,W] or [21,H,W]
    /// - Returns: 2D array of class IDs (0-20) for each pixel
    ///
    /// The model outputs logits for each of 21 classes at each pixel.
    /// This function performs argmax to get the predicted class per pixel.
    private func decode(multiArray: MLMultiArray) -> [[Int]] {
        let shape = multiArray.shape.map { $0.intValue }
        
        // Handle both 4D and 3D output shapes
        let (numClasses, height, width) = shape.count == 4
            ? (shape[1], shape[2], shape[3])  // [batch, classes, H, W]
            : (shape[0], shape[1], shape[2])  // [classes, H, W]
        
        // Direct pointer access for performance
        let ptr = multiArray.dataPointer.assumingMemoryBound(to: Float.self)
        var mask = Array(repeating: Array(repeating: 0, count: width), count: height)
        
        // Argmax across class dimension for each pixel
        for y in 0..<height {
            for x in 0..<width {
                var maxLogit: Float = -.infinity, maxClass = 0
                for c in 0..<numClasses {
                    // Index into flattened [C, H, W] array
                    let idx = c * height * width + y * width + x
                    if ptr[idx] > maxLogit { maxLogit = ptr[idx]; maxClass = c }
                }
                mask[y][x] = maxClass
            }
        }
        return mask
    }
}
*/

// MARK: - Stub Implementation (Active)
// Minimal stub to prevent compilation errors when ViT is disabled.
// Replace with the commented implementation above to enable segmentation.

/// Placeholder for disabled segmentation classes
/// Includes minimal properties required by SegmentationOverlayView
enum SegmentationClass: Int, CaseIterable {
    case background = 0
    
    var displayName: String { "Background" }
    var color: UIColor { .clear }
}

/// Placeholder result when segmentation is disabled
struct SegmentationResult {
    let mask: [[Int]] = []
    let originalSize: CGSize = .zero
    let processingTimeMs: Double = 0
    var detectedClasses: [SegmentationClass] { [] }
}

/// Stub service when ViT segmentation is disabled
@MainActor
class SegmentationService: ObservableObject {
    @Published var isEnabled = false
    @Published var lastResult: SegmentationResult?
    @Published var hasModel = false
    
    func loadModel() async {
        // ViT model loading disabled - see commented implementation above
        print("⚠️ SegmentationService: ViT implementation is commented out")
    }
    
    func segment(image: UIImage) async -> SegmentationResult? {
        // ViT segmentation disabled - see commented implementation above
        return nil
    }
}
