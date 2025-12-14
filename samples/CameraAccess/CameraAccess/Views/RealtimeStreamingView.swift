/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// RealtimeStreamingView.swift
//
// UI for real-time AI image generation from video stream.
// Shows generated images updating in real-time with stats overlay.
//

import SwiftUI

struct RealtimeStreamingView: View {
    @ObservedObject var viewModel: RealtimeStreamingViewModel
    @State private var showPromptEditor = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                // Generated image display
                if let image = viewModel.generatedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.state == .streaming {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Generating...")
                            .foregroundColor(.gray)
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 60))
                            .foregroundColor(.purple)
                        
                        Text("Real-Time AI Generation")
                            .font(.title2)
                            .foregroundColor(.white)
                        
                        Text("Tap Start to begin")
                            .foregroundColor(.gray)
                    }
                }
                
                // Stats overlay
                VStack {
                    HStack {
                        // Connection status
                        statusBadge
                        
                        Spacer()
                        
                        // Stats
                        if viewModel.state == .streaming {
                            statsView
                        }
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Controls
                    controlsView
                        .padding()
                }
            }
            .navigationTitle("Real-Time AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.stopStreaming()
                        viewModel.isActive = false
                    }
                    .foregroundColor(.white)
                }
            }
            .sheet(isPresented: $showPromptEditor) {
                promptEditorSheet
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear {
            viewModel.stopStreaming()
        }
    }
    
    // MARK: - Subviews
    
    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
    }
    
    private var statusColor: Color {
        switch viewModel.state {
        case .idle: return .gray
        case .connecting: return .yellow
        case .streaming: return .green
        case .error: return .red
        }
    }
    
    private var statusText: String {
        switch viewModel.state {
        case .idle: return "Idle"
        case .connecting: return "Connecting..."
        case .streaming: return "Live"
        case .error(let msg): return "Error: \(msg)"
        }
    }
    
    private var statsView: some View {
        HStack(spacing: 16) {
            // Inference time
            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text("\(viewModel.inferenceTimeMs)ms")
            }
            .font(.caption)
            .foregroundColor(.green)
            
            // FPS
            HStack(spacing: 4) {
                Image(systemName: "speedometer")
                Text(String(format: "%.1f fps", viewModel.fps))
            }
            .font(.caption)
            .foregroundColor(.cyan)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
    }
    
    private var controlsView: some View {
        VStack(spacing: 12) {
            // Current prompt display
            Button(action: { showPromptEditor = true }) {
                HStack {
                    Text(viewModel.prompt)
                        .font(.caption)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Image(systemName: "pencil")
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.1))
                .cornerRadius(20)
            }
            
            // Start/Stop button
            Button(action: { viewModel.toggle() }) {
                HStack {
                    Image(systemName: viewModel.state == .streaming ? "stop.fill" : "play.fill")
                    Text(viewModel.state == .streaming ? "Stop" : "Start")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 150)
                .padding()
                .background {
                    if viewModel.state == .streaming {
                        Color.red
                    } else {
                        LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing)
                    }
                }
                .cornerRadius(25)
            }
        }
    }
    
    private var promptEditorSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("Enter prompt...", text: $viewModel.prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(12)
                    .lineLimit(3...6)
                
                // Quick prompts
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickPrompts, id: \.self) { prompt in
                            Button(prompt) {
                                viewModel.updatePrompt(prompt)
                            }
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.purple.opacity(0.2))
                            .cornerRadius(16)
                            .foregroundColor(.purple)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Edit Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showPromptEditor = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private var quickPrompts: [String] {
        [
            "A cinematic photo, award winning",
            "Cyberpunk neon city at night",
            "Oil painting, renaissance style",
            "Anime artwork, studio ghibli",
            "Vintage film photography",
            "Surreal dreamscape"
        ]
    }
}
