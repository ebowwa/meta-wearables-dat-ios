/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// DepthPredictionService.swift
//
// Service for depth estimation using Depth Anything V2 CoreML model.
// Processes video frames and generates depth maps for visualization.
//

import Accelerate
import CoreImage
import CoreML
import Foundation
import UIKit
import Vision

// MARK: - Depth Prediction Service
class DepthPredictionService: ObservableObject {
    @Published var depthMapImage: UIImage?
    @Published var isProcessing: Bool = false

    private let inferenceQueue = DispatchQueue(label: "com.depthprediction.inference", qos: .userInitiated)
    private var isInferenceRunning = false
    private let targetSize = CGSize(width: 518, height: 392)
    private let context = CIContext()

    // Reusable pixel buffer for model input
    private let inputPixelBuffer: CVPixelBuffer

    // Model wrapper to handle conditional compilation
    private var modelWrapper: ModelWrapper?

    init() {
        // Create a reusable buffer to avoid allocating memory for every model invocation
        var buffer: CVPixelBuffer!
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(targetSize.width),
            Int(targetSize.height),
            kCVPixelFormatType_32ARGB,
            nil,
            &buffer
        )
        guard status == kCVReturnSuccess else {
            fatalError("Failed to create pixel buffer")
        }
        inputPixelBuffer = buffer

        setupModel()
    }

    private func setupModel() {
        // NOTE: Add DepthAnythingV2SmallF16.mlpackage to the project
        // Download from: https://huggingface.co/apple/coreml-depth-anything-v2-small
        // After adding, uncomment the HAS_DEPTH_MODEL flag below or add the model class
        modelWrapper = ModelWrapper()
        print("[DepthPrediction] Model setup pending - add DepthAnythingV2SmallF16.mlpackage to project")
    }

    func predictDepth(from image: UIImage) {
        guard let modelWrapper = modelWrapper, !isInferenceRunning else {
            return
        }

        guard let cgImage = image.cgImage else { return }

        isInferenceRunning = true
        DispatchQueue.main.async { [weak self] in
            self?.isProcessing = true
        }

        inferenceQueue.async { [weak self] in
            do {
                try self?.performInference(cgImage: cgImage, modelWrapper: modelWrapper)
            } catch {
                print("[DepthPrediction] Inference error: \(error)")
                DispatchQueue.main.async { [weak self] in
                    self?.isInferenceRunning = false
                    self?.isProcessing = false
                }
            }
        }
    }

    private func performInference(cgImage: CGImage, modelWrapper: ModelWrapper) throws {
        let ciImage = CIImage(cgImage: cgImage)
        let originalSize = CGSize(width: cgImage.width, height: cgImage.height)

        // Resize to target size
        let resizedImage = ciImage.resized(to: targetSize)

        // Render to pixel buffer
        context.render(resizedImage, to: inputPixelBuffer)

        // Run model
        let result = try modelWrapper.prediction(image: inputPixelBuffer)

        // Convert output to UIImage
        let outputCIImage = CIImage(cvPixelBuffer: result.depth)
            .resized(to: originalSize)

        if let outputCGImage = context.createCGImage(outputCIImage, from: outputCIImage.extent) {
            DispatchQueue.main.async { [weak self] in
                self?.depthMapImage = UIImage(cgImage: outputCGImage)
                self?.isInferenceRunning = false
                self?.isProcessing = false
            }
        }
    }

    // MARK: - Apply Colormap for Visualization
    func applyHeatmapColormap(to image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Draw original image
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let imageData = context.data?.bindMemory(to: UInt8.self, capacity: width * height * 4) else {
            return nil
        }

        // Apply heatmap colormap (blue -> cyan -> green -> yellow -> red)
        for i in 0..<(width * height) {
            let offset = i * 4
            let gray = Float(imageData[offset]) / 255.0

            let (r, g, b) = heatmapColor(for: gray)

            imageData[offset] = UInt8(r * 255)
            imageData[offset + 1] = UInt8(g * 255)
            imageData[offset + 2] = UInt8(b * 255)
            imageData[offset + 3] = 255
        }

        guard let outputCGImage = context.makeImage() else {
            return nil
        }

        return UIImage(cgImage: outputCGImage)
    }

    private func heatmapColor(for value: Float) -> (Float, Float, Float) {
        let clamped = max(0, min(1, value))

        if clamped < 0.25 {
            return (0, clamped * 4, 1)
        } else if clamped < 0.5 {
            return (0, 1, 1 - (clamped - 0.25) * 4)
        } else if clamped < 0.75 {
            return ((clamped - 0.5) * 4, 1, 0)
        } else {
            return (1, 1 - (clamped - 0.75) * 4, 0)
        }
    }
}

// MARK: - Model Wrapper
// This wrapper allows the code to build without the model present
// After adding DepthAnythingV2SmallF16.mlpackage to the project,
// Xcode will auto-generate the DepthAnythingV2SmallF16 class
private class ModelWrapper {
    private var model: Any?

    init() {
        // Attempt to load the model - will fail gracefully if not present
        do {
            model = try DepthAnythingV2SmallF16()
            print("[DepthPrediction] Depth Anything V2 model loaded")
        } catch {
            print("[DepthPrediction] Model not available: \(error)")
        }
    }

    func prediction(image: CVPixelBuffer) throws -> ModelOutput {
        guard let depthModel = model as? DepthAnythingV2SmallF16 else {
            throw ModelError.notLoaded
        }
        let result = try depthModel.prediction(image: image)
        return ModelOutput(depth: result.depth)
    }
}

private struct ModelOutput {
    let depth: CVPixelBuffer
}

private enum ModelError: Error {
    case notLoaded
}

// MARK: - CIImage Extensions
fileprivate extension CIImage {
    func resized(to size: CGSize) -> CIImage {
        let outputScaleX = size.width / extent.width
        let outputScaleY = size.height / extent.height
        var outputImage = self.transformed(by: CGAffineTransform(scaleX: outputScaleX, y: outputScaleY))
        outputImage = outputImage.transformed(
            by: CGAffineTransform(translationX: -outputImage.extent.origin.x, y: -outputImage.extent.origin.y)
        )
        return outputImage
    }
}
