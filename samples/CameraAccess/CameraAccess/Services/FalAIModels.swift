/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// FalAIModels.swift
//
// Data models for fal.ai Fast SDXL API integration.
// Matches the schema at https://fal.ai/models/fal-ai/fast-sdxl/api
//

import Foundation

// MARK: - Request Models

/// Image size options for fal.ai SDXL generation
enum FalImageSize: String, Codable, CaseIterable {
    case squareHD = "square_hd"
    case square = "square"
    case portrait4x3 = "portrait_4_3"
    case portrait16x9 = "portrait_16_9"
    case landscape4x3 = "landscape_4_3"
    case landscape16x9 = "landscape_16_9"
    
    var displayName: String {
        switch self {
        case .squareHD: return "Square HD"
        case .square: return "Square"
        case .portrait4x3: return "Portrait 4:3"
        case .portrait16x9: return "Portrait 16:9"
        case .landscape4x3: return "Landscape 4:3"
        case .landscape16x9: return "Landscape 16:9"
        }
    }
}

/// Image format options
enum FalImageFormat: String, Codable {
    case jpeg
    case png
}

/// Request body for fal.ai Fast SDXL API
struct FalAIRequest: Encodable {
    let prompt: String
    let negativePrompt: String?
    let imageSize: String
    let numInferenceSteps: Int
    let guidanceScale: Float
    let numImages: Int
    let enableSafetyChecker: Bool
    let format: String
    
    enum CodingKeys: String, CodingKey {
        case prompt
        case negativePrompt = "negative_prompt"
        case imageSize = "image_size"
        case numInferenceSteps = "num_inference_steps"
        case guidanceScale = "guidance_scale"
        case numImages = "num_images"
        case enableSafetyChecker = "enable_safety_checker"
        case format
    }
    
    init(
        prompt: String,
        negativePrompt: String? = nil,
        imageSize: FalImageSize = .squareHD,
        numInferenceSteps: Int = 25,
        guidanceScale: Float = 7.5,
        numImages: Int = 1,
        enableSafetyChecker: Bool = false,
        format: FalImageFormat = .jpeg
    ) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.imageSize = imageSize.rawValue
        self.numInferenceSteps = numInferenceSteps
        self.guidanceScale = guidanceScale
        self.numImages = numImages
        self.enableSafetyChecker = enableSafetyChecker
        self.format = format.rawValue
    }
}

// MARK: - Response Models

/// Individual generated image from fal.ai
struct FalGeneratedImage: Decodable {
    let url: String
    let width: Int?
    let height: Int?
    let contentType: String?
    
    enum CodingKeys: String, CodingKey {
        case url
        case width
        case height
        case contentType = "content_type"
    }
}

/// Response from fal.ai Fast SDXL API
struct FalAIResponse: Decodable {
    let images: [FalGeneratedImage]
    let seed: Int?
    let prompt: String?
    let hasNsfwConcepts: [Bool]?
    
    enum CodingKeys: String, CodingKey {
        case images
        case seed
        case prompt
        case hasNsfwConcepts = "has_nsfw_concepts"
    }
}

// MARK: - Queue API Models

/// Response when submitting to queue
struct FalQueueSubmitResponse: Decodable {
    let requestId: String
    
    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
    }
}

/// Status response for queue polling
struct FalQueueStatusResponse: Decodable {
    let status: String
    let responseUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case status
        case responseUrl = "response_url"
    }
}

// MARK: - Error Models

/// Errors specific to fal.ai API operations
enum FalAIError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case requestFailed(statusCode: Int, message: String?)
    case decodingFailed(Error)
    case imageDownloadFailed
    case timeout
    case nsfwContentDetected
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "fal.ai API key is not configured. Set FAL_KEY environment variable."
        case .invalidResponse:
            return "Received an invalid response from fal.ai."
        case .requestFailed(let statusCode, let message):
            return "Request failed with status \(statusCode): \(message ?? "Unknown error")"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .imageDownloadFailed:
            return "Failed to download the generated image."
        case .timeout:
            return "Request timed out. Please try again."
        case .nsfwContentDetected:
            return "NSFW content was detected. Please modify your prompt."
        }
    }
}
