/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// AIPromptInputView.swift
//
// UI for entering prompts for AI image generation using fal.ai SDXL.
// Allows the user to describe the desired transformation or style.
//

import SwiftUI

struct AIPromptInputView: View {
    @ObservedObject var viewModel: AIImageGenerationViewModel
    @FocusState private var isPromptFocused: Bool
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black.opacity(0.95)
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Source image preview (thumbnail)
                    if let sourceImage = viewModel.sourceImage {
                        Image(uiImage: sourceImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 150)
                            .cornerRadius(12)
                            .shadow(color: .white.opacity(0.1), radius: 10)
                    }
                    
                    // Main prompt input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Describe your vision")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        TextField("e.g., transform into a cyberpunk cityscape", text: $viewModel.prompt, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                            .foregroundColor(.white)
                            .lineLimit(3...6)
                            .focused($isPromptFocused)
                    }
                    
                    // Negative prompt toggle and input
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $viewModel.showNegativePrompt) {
                            Text("Add negative prompt")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        
                        if viewModel.showNegativePrompt {
                            TextField("What to avoid...", text: $viewModel.negativePrompt)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                                .foregroundColor(.white)
                        }
                    }
                    
                    // Image size picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Image Size")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Picker("Size", selection: $viewModel.selectedImageSize) {
                            ForEach(FalImageSize.allCases, id: \.self) { size in
                                Text(size.displayName).tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                        .colorMultiply(.white)
                    }
                    
                    Spacer()
                    
                    // Generate button
                    Button(action: {
                        Task {
                            await viewModel.generate()
                        }
                    }) {
                        HStack {
                            Image(systemName: "wand.and.stars")
                            Text("Generate")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            viewModel.canGenerate
                            ? LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            : LinearGradient(
                                colors: [.gray, .gray.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                    }
                    .disabled(!viewModel.canGenerate)
                }
                .padding()
            }
            .navigationTitle("AI Generation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        viewModel.dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .onAppear {
                isPromptFocused = true
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Preview Prompts

/// Quick prompts for inspiration
struct QuickPromptsView: View {
    let onSelect: (String) -> Void
    
    private let prompts = [
        "Transform into oil painting style",
        "Make it look like a movie poster",
        "Convert to cyberpunk aesthetic",
        "Render as anime artwork",
        "Apply vintage film look"
    ]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(prompts, id: \.self) { prompt in
                    Button(action: { onSelect(prompt) }) {
                        Text(prompt)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(16)
                            .foregroundColor(.white)
                    }
                }
            }
        }
    }
}
