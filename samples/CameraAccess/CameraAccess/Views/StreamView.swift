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

      // Video backdrop - side by side with depth map when enabled
      if let videoFrame = viewModel.currentVideoFrame, viewModel.hasReceivedFirstFrame {
        GeometryReader { geometry in
          if viewModel.showDepthPrediction {
            // Side-by-side view: video + depth map
            HStack(spacing: 0) {
              // Original video
              Image(uiImage: videoFrame)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: geometry.size.width / 2)
                .clipped()

              // Depth map
              if let depthMap = viewModel.currentDepthMap {
                Image(uiImage: depthMap)
                  .resizable()
                  .aspectRatio(contentMode: .fill)
                  .frame(maxWidth: geometry.size.width / 2)
                  .clipped()
              } else if viewModel.isProcessingDepthPrediction {
                // Loading indicator for depth map
                  ZStack {
                    Color.black.opacity(0.3)
                    ProgressView()
                      .foregroundColor(.white)
                  }
                  .frame(maxWidth: geometry.size.width / 2)
              } else {
                // Placeholder when depth prediction is off
                Color.black.opacity(0.3)
                  .frame(maxWidth: geometry.size.width / 2)
                  .overlay(
                    Text("Depth Map")
                      .foregroundColor(.white.opacity(0.5))
                  )
              }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
          } else {
            // Full video view (original behavior)
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
      Task {
        if viewModel.streamingStatus != .stopped {
          await viewModel.stopSession()
        }
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
        Task {
          await viewModel.stopSession()
        }
      }

      // Timer button
      CircleButton(
        icon: "timer",
        text: viewModel.activeTimeLimit != .noLimit ? viewModel.activeTimeLimit.displayText : nil
      ) {
        let nextTimeLimit = viewModel.activeTimeLimit.next
        viewModel.setTimeLimit(nextTimeLimit)
      }

      // Depth prediction toggle button
      CircleButton(
        icon: viewModel.showDepthPrediction ? "cube.fill" : "cube",
        text: nil
      ) {
        viewModel.toggleDepthPrediction()
      }

      // Photo button
      CircleButton(icon: "camera.fill", text: nil) {
        viewModel.capturePhoto()
      }
    }
  }
}
