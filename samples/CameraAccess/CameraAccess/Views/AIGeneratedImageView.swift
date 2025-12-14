/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// AIGeneratedImageView.swift
//
// Displays the AI-generated image result from fal.ai SDXL.
// Provides options to save, share, or regenerate.
//

import SwiftUI

struct AIGeneratedImageView: View {
    @ObservedObject var viewModel: AIImageGenerationViewModel
    @State private var showShareSheet = false
    @State private var showSaveSuccess = false
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Generated image with zoom gesture
                    if let image = viewModel.generatedImage {
                        GeometryReader { geometry in
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                                .scaleEffect(scale)
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            scale = value.magnitude
                                        }
                                        .onEnded { _ in
                                            withAnimation(.spring()) {
                                                scale = 1.0
                                            }
                                        }
                                )
                                .cornerRadius(16)
                                .shadow(color: .purple.opacity(0.3), radius: 20)
                        }
                    }
                    
                    // Used prompt display
                    Text("\"\(viewModel.prompt)\"")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .italic()
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Spacer()
                    
                    // Action buttons
                    HStack(spacing: 16) {
                        // Save button
                        ActionButton(
                            icon: "square.and.arrow.down",
                            title: "Save"
                        ) {
                            Task {
                                if await viewModel.saveToPhotos() {
                                    showSaveSuccess = true
                                }
                            }
                        }
                        
                        // Share button
                        ActionButton(
                            icon: "square.and.arrow.up",
                            title: "Share"
                        ) {
                            showShareSheet = true
                        }
                        
                        // Regenerate button
                        ActionButton(
                            icon: "arrow.clockwise",
                            title: "Retry"
                        ) {
                            Task {
                                await viewModel.regenerate()
                            }
                        }
                        
                        // New prompt button
                        ActionButton(
                            icon: "text.cursor",
                            title: "New"
                        ) {
                            viewModel.tryAgain()
                        }
                    }
                    .padding(.horizontal)
                }
                .padding()
                
                // Save success overlay
                if showSaveSuccess {
                    SaveSuccessOverlay {
                        showSaveSuccess = false
                    }
                }
            }
            .navigationTitle("AI Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let image = viewModel.generatedImage {
                    ShareSheet(photo: image)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(title)
                    .font(.caption2)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.15))
            .cornerRadius(12)
        }
    }
}

// MARK: - Save Success Overlay

struct SaveSuccessOverlay: View {
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            Text("Saved to Photos")
                .font(.headline)
                .foregroundColor(.white)
        }
        .padding(32)
        .background(Color.black.opacity(0.8))
        .cornerRadius(20)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                onDismiss()
            }
        }
    }
}

// MARK: - Generating View

struct AIGeneratingView: View {
    @ObservedObject var viewModel: AIImageGenerationViewModel
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Source image thumbnail
                if let sourceImage = viewModel.sourceImage {
                    Image(uiImage: sourceImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 150)
                        .cornerRadius(12)
                        .opacity(0.5)
                }
                
                // Loading animation
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                
                // Progress message
                Text(viewModel.progressMessage)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                // Prompt being used
                Text("\"\(viewModel.prompt)\"")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .italic()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Error View

struct AIErrorView: View {
    let errorMessage: String
    let onRetry: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                Text("Generation Failed")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(errorMessage)
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                HStack(spacing: 16) {
                    Button(action: onRetry) {
                        Text("Try Again")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    
                    Button(action: onDismiss) {
                        Text("Cancel")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
            }
        }
        .preferredColorScheme(.dark)
    }
}
