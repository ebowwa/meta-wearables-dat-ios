/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// AIImageGenerationViewModel.swift
//
// View model for orchestrating AI image generation from captured camera frames.
// Manages the flow: source image → prompt input → fal.ai generation → display result
//

import Photos
import SwiftUI

/// State for the AI generation flow
enum AIGenerationState: Equatable {
    case idle
    case promptInput
    case generating
    case completed
    case error(String)
    
    static func == (lhs: AIGenerationState, rhs: AIGenerationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.promptInput, .promptInput),
             (.generating, .generating), (.completed, .completed):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

@MainActor
class AIImageGenerationViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    /// The source image captured from Meta glasses
    @Published var sourceImage: UIImage?
    
    /// The AI-generated result image
    @Published var generatedImage: UIImage?
    
    /// User-entered prompt for generation
    @Published var prompt: String = ""
    
    /// Optional negative prompt
    @Published var negativePrompt: String = ""
    
    /// Show negative prompt input field
    @Published var showNegativePrompt: Bool = false
    
    /// Selected image size for generation
    @Published var selectedImageSize: FalImageSize = .squareHD
    
    /// Current state of the generation flow
    @Published var state: AIGenerationState = .idle
    
    /// Progress message during generation
    @Published var progressMessage: String = ""
    
    // MARK: - Computed Properties
    
    var isGenerating: Bool {
        state == .generating
    }
    
    var hasResult: Bool {
        generatedImage != nil
    }
    
    var canGenerate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Public Methods
    
    /// Start the generation flow with a captured image
    func startWithImage(_ image: UIImage) {
        sourceImage = image
        generatedImage = nil
        prompt = ""
        negativePrompt = ""
        state = .promptInput
    }
    
    /// Generate an image based on the current prompt
    func generate() async {
        guard canGenerate else { return }
        
        state = .generating
        progressMessage = "Sending request to fal.ai..."
        
        do {
            progressMessage = "Generating image..."
            
            let result = try await FalAIService.shared.generateImage(
                prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                negativePrompt: showNegativePrompt ? negativePrompt : nil,
                imageSize: selectedImageSize
            )
            
            generatedImage = result
            state = .completed
            progressMessage = ""
            
        } catch let error as FalAIError {
            state = .error(error.localizedDescription)
            progressMessage = ""
        } catch {
            state = .error("An unexpected error occurred: \(error.localizedDescription)")
            progressMessage = ""
        }
    }
    
    /// Regenerate with the same prompt
    func regenerate() async {
        await generate()
    }
    
    /// Reset and try again with a new prompt
    func tryAgain() {
        generatedImage = nil
        state = .promptInput
    }
    
    /// Save the generated image to Photos
    func saveToPhotos() async -> Bool {
        guard let image = generatedImage else { return false }
        
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    guard status == .authorized || status == .limited else {
                        continuation.resume(throwing: NSError(
                            domain: "AIImageGeneration",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Photos access denied"]
                        ))
                        return
                    }
                    
                    PHPhotoLibrary.shared().performChanges {
                        PHAssetCreationRequest.creationRequestForAsset(from: image)
                    } completionHandler: { success, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if success {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: NSError(
                                domain: "AIImageGeneration",
                                code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "Failed to save photo"]
                            ))
                        }
                    }
                }
            }
            return true
        } catch {
            return false
        }
    }
    
    /// Dismiss and reset the entire flow
    func dismiss() {
        sourceImage = nil
        generatedImage = nil
        prompt = ""
        negativePrompt = ""
        showNegativePrompt = false
        state = .idle
        progressMessage = ""
    }
    
    /// Dismiss error state
    func dismissError() {
        if case .error = state {
            state = .promptInput
        }
    }
}
