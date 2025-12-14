/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// RealtimeStreamingViewModel.swift
//
// ViewModel for real-time AI image generation from video stream.
// Continuously sends prompts and displays generated images in real-time.
//

import SwiftUI

/// State for real-time streaming
enum RealtimeStreamingState: Equatable {
    case idle
    case connecting
    case streaming
    case error(String)
}

@MainActor
class RealtimeStreamingViewModel: ObservableObject, FalRealtimeDelegate {
    
    // MARK: - Published Properties
    
    /// The generated AI image (updates in real-time)
    @Published var generatedImage: UIImage?
    
    /// The prompt being used for generation
    @Published var prompt: String = "A cinematic photo, award winning photography"
    
    /// Current streaming state
    @Published var state: RealtimeStreamingState = .idle
    
    /// Latest inference time in milliseconds
    @Published var inferenceTimeMs: Int = 0
    
    /// Show the real-time view
    @Published var isActive: Bool = false
    
    /// Frame rate tracking
    @Published var fps: Double = 0
    
    // MARK: - Private Properties
    
    private let realtimeService = FalRealtimeService()
    private var frameCount: Int = 0
    private var fpsTimer: Timer?
    private var lastFpsUpdate: Date = Date()
    
    // MARK: - Initialization
    
    init() {
        realtimeService.delegate = self
    }
    
    // MARK: - Public Methods
    
    /// Start real-time streaming
    func startStreaming() {
        state = .connecting
        realtimeService.connect()
        startFPSTracking()
    }
    
    /// Stop real-time streaming
    func stopStreaming() {
        realtimeService.disconnect()
        stopFPSTracking()
        state = .idle
        generatedImage = nil
    }
    
    /// Update the prompt (triggers new generation)
    func updatePrompt(_ newPrompt: String) {
        prompt = newPrompt
        if state == .streaming {
            sendGeneration()
        }
    }
    
    /// Send a generation request with current prompt
    func sendGeneration() {
        let seed = Int.random(in: 0..<10_000_000)
        realtimeService.send(prompt: prompt, seed: seed, steps: 2)
    }
    
    /// Toggle streaming on/off
    func toggle() {
        if state == .streaming || state == .connecting {
            stopStreaming()
        } else {
            startStreaming()
        }
    }
    
    // MARK: - FPS Tracking
    
    private func startFPSTracking() {
        frameCount = 0
        lastFpsUpdate = Date()
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.fps = Double(self.frameCount)
                self.frameCount = 0
            }
        }
    }
    
    private func stopFPSTracking() {
        fpsTimer?.invalidate()
        fpsTimer = nil
        fps = 0
    }
    
    // MARK: - FalRealtimeDelegate
    
    nonisolated func falRealtime(_ service: FalRealtimeService, didReceiveImage image: UIImage, inferenceTime: TimeInterval) {
        Task { @MainActor in
            self.generatedImage = image
            self.inferenceTimeMs = Int(inferenceTime * 1000)
            self.frameCount += 1
            
            // Immediately request next frame for continuous streaming
            self.sendGeneration()
        }
    }
    
    nonisolated func falRealtime(_ service: FalRealtimeService, didEncounterError error: Error) {
        Task { @MainActor in
            self.state = .error(error.localizedDescription)
        }
    }
    
    nonisolated func falRealtimeDidConnect(_ service: FalRealtimeService) {
        Task { @MainActor in
            self.state = .streaming
            // Start the generation loop
            self.sendGeneration()
        }
    }
    
    nonisolated func falRealtimeDidDisconnect(_ service: FalRealtimeService) {
        Task { @MainActor in
            if self.state != .idle {
                self.state = .idle
            }
        }
    }
}
