/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// FalRealtimeService.swift
//
// WebSocket-based real-time image generation using fal.ai Flux Schnell.
// Enables streaming generation as frames come in from Meta glasses.
//
// Based on: https://fal.ai/models/fal-ai/flux-schnell-realtime
//

import Foundation
import UIKit

/// Delegate for real-time image generation events
protocol FalRealtimeDelegate: AnyObject {
    func falRealtime(_ service: FalRealtimeService, didReceiveImage image: UIImage, inferenceTime: TimeInterval)
    func falRealtime(_ service: FalRealtimeService, didEncounterError error: Error)
    func falRealtimeDidConnect(_ service: FalRealtimeService)
    func falRealtimeDidDisconnect(_ service: FalRealtimeService)
}

/// Real-time image generation service using WebSocket connection to fal.ai
class FalRealtimeService: NSObject {
    
    // MARK: - Properties
    
    weak var delegate: FalRealtimeDelegate?
    
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    
    // Correct WebSocket URL for fal.ai realtime
    private let baseURL = "wss://ws.fal.run/fal-ai/flux-schnell/realtime"
    private let throttleInterval: TimeInterval = 0.064 // ~15fps
    
    private var lastSendTime: Date = .distantPast
    private var pendingInput: RealtimeInput?
    private var isConnected = false
    
    // API Key
    private var apiKey: String {
        if let envKey = ProcessInfo.processInfo.environment["FAL_KEY"], !envKey.isEmpty {
            return envKey
        }
        return "YOUR_FAL_KEY_HERE"
    }
    
    // MARK: - Input/Output Models
    
    struct RealtimeInput: Codable {
        let prompt: String
        let seed: Int?
        let imageSize: ImageSize?
        let numInferenceSteps: Int
        let enableSafetyChecker: Bool
        let syncMode: Bool
        
        struct ImageSize: Codable {
            let width: Int
            let height: Int
        }
        
        enum CodingKeys: String, CodingKey {
            case prompt
            case seed
            case imageSize = "image_size"
            case numInferenceSteps = "num_inference_steps"
            case enableSafetyChecker = "enable_safety_checker"
            case syncMode = "sync_mode"
        }
        
        init(
            prompt: String,
            seed: Int? = nil,
            width: Int = 512,
            height: Int = 512,
            numInferenceSteps: Int = 2,
            enableSafetyChecker: Bool = false
        ) {
            self.prompt = prompt
            self.seed = seed
            self.imageSize = ImageSize(width: width, height: height)
            self.numInferenceSteps = numInferenceSteps
            self.enableSafetyChecker = enableSafetyChecker
            self.syncMode = true
        }
    }
    
    struct RealtimeOutput: Codable {
        let images: [ImageData]?
        let timings: Timings?
        let error: String?
        
        struct ImageData: Codable {
            let url: String?
            let content: String? // Base64 encoded
            let contentType: String?
            
            enum CodingKeys: String, CodingKey {
                case url
                case content
                case contentType = "content_type"
            }
        }
        
        struct Timings: Codable {
            let inference: Double?
        }
    }
    
    // MARK: - Connection Management
    
    func connect() {
        guard !isConnected else { return }
        
        guard let url = URL(string: baseURL) else {
            delegate?.falRealtime(self, didEncounterError: NSError(
                domain: "FalRealtime",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid WebSocket URL"]
            ))
            return
        }
        
        // Create URL request with Authorization header
        var request = URLRequest(url: url)
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let configuration = URLSessionConfiguration.default
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        
        webSocket = session?.webSocketTask(with: request)
        webSocket?.resume()
        
        receiveMessage()
    }
    
    func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session = nil
        isConnected = false
        delegate?.falRealtimeDidDisconnect(self)
    }
    
    // MARK: - Sending Requests
    
    /// Send a generation request with throttling
    func send(prompt: String, seed: Int? = nil, steps: Int = 2) {
        let input = RealtimeInput(
            prompt: prompt,
            seed: seed,
            numInferenceSteps: steps
        )
        
        // Throttle requests
        let now = Date()
        if now.timeIntervalSince(lastSendTime) >= throttleInterval {
            sendImmediate(input)
            lastSendTime = now
        } else {
            // Queue for later
            pendingInput = input
            DispatchQueue.main.asyncAfter(deadline: .now() + throttleInterval) { [weak self] in
                guard let self, let pending = self.pendingInput else { return }
                self.sendImmediate(pending)
                self.pendingInput = nil
                self.lastSendTime = Date()
            }
        }
    }
    
    private func sendImmediate(_ input: RealtimeInput) {
        guard isConnected else {
            connect()
            // Queue the input to send after connection
            pendingInput = input
            return
        }
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(input)
            let message = URLSessionWebSocketTask.Message.data(data)
            
            webSocket?.send(message) { [weak self] error in
                if let error = error {
                    self?.delegate?.falRealtime(self!, didEncounterError: error)
                }
            }
        } catch {
            delegate?.falRealtime(self, didEncounterError: error)
        }
    }
    
    // MARK: - Receiving Messages
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            guard let self else { return }
            
            switch result {
            case .success(let message):
                self.handleMessage(message)
                // Continue receiving
                self.receiveMessage()
                
            case .failure(let error):
                self.delegate?.falRealtime(self, didEncounterError: error)
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        
        switch message {
        case .data(let d):
            data = d
        case .string(let s):
            guard let d = s.data(using: .utf8) else { return }
            data = d
        @unknown default:
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let output = try decoder.decode(RealtimeOutput.self, from: data)
            
            if let error = output.error {
                delegate?.falRealtime(self, didEncounterError: NSError(
                    domain: "FalRealtime",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: error]
                ))
                return
            }
            
            guard let imageData = output.images?.first else { return }
            
            // Handle base64 encoded image content
            if let base64Content = imageData.content,
               let imageBytes = Data(base64Encoded: base64Content),
               let image = UIImage(data: imageBytes) {
                let inferenceTime = output.timings?.inference ?? 0
                delegate?.falRealtime(self, didReceiveImage: image, inferenceTime: inferenceTime)
            }
            // Handle URL-based image
            else if let urlString = imageData.url, let url = URL(string: urlString) {
                Task {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        if let image = UIImage(data: data) {
                            await MainActor.run {
                                let inferenceTime = output.timings?.inference ?? 0
                                self.delegate?.falRealtime(self, didReceiveImage: image, inferenceTime: inferenceTime)
                            }
                        }
                    } catch {
                        await MainActor.run {
                            self.delegate?.falRealtime(self, didEncounterError: error)
                        }
                    }
                }
            }
        } catch {
            delegate?.falRealtime(self, didEncounterError: error)
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension FalRealtimeService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        isConnected = true
        delegate?.falRealtimeDidConnect(self)
        
        // Send any pending input
        if let pending = pendingInput {
            sendImmediate(pending)
            pendingInput = nil
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        delegate?.falRealtimeDidDisconnect(self)
    }
}
