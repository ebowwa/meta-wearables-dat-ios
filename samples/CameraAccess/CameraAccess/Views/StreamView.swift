/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamView.swift
//
// Main UI for video streaming from Meta wearable devices using the DAT SDK.
// This view demonstrates the complete streaming API: video streaming with real-time display, photo capture,
// and error handling.
//

import MWDATCore
import SwiftUI

struct StreamView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var wearablesVM: WearablesViewModel

  var body: some View {
    ZStack {
      // Black background for letterboxing/pillarboxing
      Color.black
        .edgesIgnoringSafeArea(.all)

      // Video backdrop - show original or AI transformed frame
      if viewModel.hasReceivedFirstFrame {
        GeometryReader { geometry in
          // When AI mode is on and we have a transformed frame, show it
          // Otherwise show the original video frame
          if viewModel.aiModeEnabled, let aiFrame = viewModel.aiTransformedFrame {
            Image(uiImage: aiFrame)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: geometry.size.width, height: geometry.size.height)
              .clipped()
          } else if let videoFrame = viewModel.currentVideoFrame {
            Image(uiImage: videoFrame)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: geometry.size.width, height: geometry.size.height)
              .clipped()
          }
        }
        .edgesIgnoringSafeArea(.all)
      } else {
        ProgressView()
          .scaleEffect(1.5)
          .foregroundColor(.white)
      }

      // AI Mode stats overlay (top of screen)
      if viewModel.aiModeEnabled {
        VStack {
          HStack {
            // AI mode indicator
            HStack(spacing: 6) {
              Circle()
                .fill(viewModel.aiTransformedFrame != nil ? Color.green : Color.yellow)
                .frame(width: 8, height: 8)
              Text("AI Live")
                .font(.caption.bold())
                .foregroundColor(.white)
              if viewModel.aiInferenceTimeMs > 0 {
                Text("• \(viewModel.aiInferenceTimeMs)ms")
                  .font(.caption)
                  .foregroundColor(.green)
              }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.7))
            .cornerRadius(16)

            Spacer()
          }
          .padding(.horizontal)
          .padding(.top, 60)

          Spacer()
        }
      }

      // Bottom controls layer

      VStack {
        Spacer()
        ControlsView(viewModel: viewModel)
      }
      .padding(.all, 24)
      // Timer display area with fixed height
      VStack {
        Spacer()
        if viewModel.activeTimeLimit.isTimeLimited && viewModel.remainingTime > 0 {
          Text("Streaming ending in \(viewModel.remainingTime.formattedCountdown)")
            .font(.system(size: 15))
            .foregroundColor(.white)
        }
      }
    }
    .onDisappear {
      if viewModel.streamingStatus != .stopped {
        viewModel.stopSession()
      }
    }
    // Show captured photos from DAT SDK in a preview sheet
    .sheet(isPresented: $viewModel.showPhotoPreview) {
      if let photo = viewModel.capturedPhoto {
        PhotoPreviewView(
          photo: photo,
          onDismiss: {
            viewModel.dismissPhotoPreview()
          }
        )
      }
    }
    // Show AI generation flow in a full-screen sheet
    .fullScreenCover(isPresented: $viewModel.showAIGeneration) {
      AIImageFlowView(viewModel: viewModel.aiGenerationViewModel)
        .onDisappear {
          if viewModel.aiGenerationViewModel.state == .idle {
            viewModel.showAIGeneration = false
          }
        }
    }
    // Show real-time AI streaming
    .fullScreenCover(isPresented: $viewModel.showRealtimeStreaming) {
      RealtimeStreamingView(viewModel: viewModel.realtimeStreamingViewModel)
        .onDisappear {
          viewModel.showRealtimeStreaming = false
        }
    }
  }
}

// Extracted controls for clarity
struct ControlsView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  var body: some View {
    // Controls row
    HStack(spacing: 8) {
      CustomButton(
        title: "Stop streaming",
        style: .destructive,
        isDisabled: false
      ) {
        viewModel.stopSession()
      }

      // Timer button
      CircleButton(
        icon: "timer",
        text: viewModel.activeTimeLimit != .noLimit ? viewModel.activeTimeLimit.displayText : nil
      ) {
        let nextTimeLimit = viewModel.activeTimeLimit.next
        viewModel.setTimeLimit(nextTimeLimit)
      }

      // Photo button
      CircleButton(icon: "camera.fill", text: nil) {
        viewModel.capturePhoto()
      }

      // AI Generation button (single image)
      CircleButton(icon: "wand.and.stars", text: nil) {
        viewModel.captureForAIGeneration()
      }

      // Real-time AI mode toggle (inline during stream)
      CircleButton(
        icon: viewModel.aiModeEnabled ? "bolt.slash.fill" : "bolt.fill",
        text: viewModel.aiModeEnabled ? "ON" : nil
      ) {
        viewModel.toggleAIMode()
      }
    }
  }
}
