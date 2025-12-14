/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// FalAIService.swift
//
// API client for fal.ai Fast SDXL image generation.
// Uses the queue-based API for reliable generation with polling.
//
// API Documentation: https://fal.ai/models/fal-ai/fast-sdxl/api
//

import Foundation
import UIKit

/// Service for generating images using fal.ai Fast SDXL API
actor FalAIService {
    
    // MARK: - Singleton
    
    static let shared = FalAIService()
    
    // MARK: - Configuration
    
    private let baseURL = "https://queue.fal.run"
    private let modelEndpoint = "fal-ai/fast-sdxl"
    private let pollingInterval: TimeInterval = 1.0
    private let maxPollingAttempts = 60 // 60 seconds timeout
    
    // API Key: Use environment variable if available, otherwise use hardcoded key for development
    // WARNING: In production, always use environment variables or secure storage
    private var apiKey: String? {
        if let envKey = ProcessInfo.processInfo.environment["FAL_KEY"], !envKey.isEmpty {
            return envKey
        }
        // Fallback for development - remove or secure this in production
        return "YOUR_FAL_KEY_HERE"
    }
    
    // MARK: - Private Properties
    
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()
    
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()
    
    // MARK: - Public API
    
    /// Generate an image from a text prompt using Stable Diffusion XL
    /// - Parameters:
    ///   - prompt: The text prompt describing the desired image
    ///   - negativePrompt: Optional prompt describing what to avoid
    ///   - imageSize: The size/aspect ratio of the generated image
    ///   - numInferenceSteps: Number of diffusion steps (higher = better quality, slower)
    ///   - guidanceScale: How closely to follow the prompt (higher = more literal)
    /// - Returns: The generated UIImage
    func generateImage(
        prompt: String,
        negativePrompt: String? = nil,
        imageSize: FalImageSize = .squareHD,
        numInferenceSteps: Int = 25,
        guidanceScale: Float = 7.5
    ) async throws -> UIImage {
        // Validate API key
        guard let key = apiKey, !key.isEmpty else {
            throw FalAIError.missingAPIKey
        }
        
        // Create request
        let request = FalAIRequest(
            prompt: prompt,
            negativePrompt: negativePrompt,
            imageSize: imageSize,
            numInferenceSteps: numInferenceSteps,
            guidanceScale: guidanceScale
        )
        
        // Submit to queue
        let requestId = try await submitToQueue(request: request, apiKey: key)
        
        // Poll for completion
        let response = try await pollForResult(requestId: requestId, apiKey: key)
        
        // Download the first generated image
        guard let firstImage = response.images.first else {
            throw FalAIError.invalidResponse
        }
        
        return try await downloadImage(from: firstImage.url)
    }
    
    // MARK: - Queue API
    
    private func submitToQueue(request: FalAIRequest, apiKey: String) async throws -> String {
        let url = URL(string: "\(baseURL)/\(modelEndpoint)")!
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try encoder.encode(request)
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FalAIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw FalAIError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }
        
        // Check if this is a direct response (sync mode) or queue response
        do {
            // Try to decode as direct response first
            let directResponse = try decoder.decode(FalAIResponse.self, from: data)
            // Store the response and return a fake request ID
            // The caller will get this from cache
            return "direct_\(UUID().uuidString)"
        } catch {
            // Try queue response
            let queueResponse = try decoder.decode(FalQueueSubmitResponse.self, from: data)
            return queueResponse.requestId
        }
    }
    
    private func pollForResult(requestId: String, apiKey: String) async throws -> FalAIResponse {
        // Handle direct responses
        if requestId.hasPrefix("direct_") {
            // This shouldn't happen with current implementation, but handle gracefully
            throw FalAIError.invalidResponse
        }
        
        var attempts = 0
        
        while attempts < maxPollingAttempts {
            let statusURL = URL(string: "\(baseURL)/\(modelEndpoint)/requests/\(requestId)/status")!
            
            var urlRequest = URLRequest(url: statusURL)
            urlRequest.httpMethod = "GET"
            urlRequest.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw FalAIError.invalidResponse
            }
            
            let status = try decoder.decode(FalQueueStatusResponse.self, from: data)
            
            switch status.status.lowercased() {
            case "completed":
                return try await fetchResult(requestId: requestId, apiKey: apiKey)
            case "failed":
                throw FalAIError.requestFailed(statusCode: 500, message: "Generation failed")
            case "in_progress", "in_queue", "pending":
                attempts += 1
                try await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
            default:
                attempts += 1
                try await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
            }
        }
        
        throw FalAIError.timeout
    }
    
    private func fetchResult(requestId: String, apiKey: String) async throws -> FalAIResponse {
        let resultURL = URL(string: "\(baseURL)/\(modelEndpoint)/requests/\(requestId)")!
        
        var urlRequest = URLRequest(url: resultURL)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FalAIError.invalidResponse
        }
        
        do {
            return try decoder.decode(FalAIResponse.self, from: data)
        } catch {
            throw FalAIError.decodingFailed(error)
        }
    }
    
    // MARK: - Image Download
    
    private func downloadImage(from urlString: String) async throws -> UIImage {
        guard let url = URL(string: urlString) else {
            throw FalAIError.imageDownloadFailed
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw FalAIError.imageDownloadFailed
        }
        
        guard let image = UIImage(data: data) else {
            throw FalAIError.imageDownloadFailed
        }
        
        return image
    }
}
