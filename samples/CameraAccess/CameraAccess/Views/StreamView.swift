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

      // Video backdrop
      if let videoFrame = viewModel.currentVideoFrame, viewModel.hasReceivedFirstFrame {
        GeometryReader { geometry in
          ZStack {
            Image(uiImage: videoFrame)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: geometry.size.width, height: geometry.size.height)
              .clipped()
            
            // Bounding box overlay for detected objects
            if viewModel.detectionModeEnabled {
              ForEach(viewModel.detectedObjects) { obj in
                let rect = obj.boundingBoxForView(size: geometry.size)
                BoundingBoxView(object: obj, rect: rect)
              }
            }
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

      // Photo button
      CircleButton(icon: "camera.fill", text: nil) {
        viewModel.capturePhoto()
      }

      // Object detection button
      CircleButton(
        icon: viewModel.detectionModeEnabled ? "eye.slash.fill" : "eye.fill",
        text: viewModel.detectionModeEnabled ? "ON" : nil
      ) {
        viewModel.toggleDetectionMode()
      }
    }
  }
}

// MARK: - Bounding Box View

struct BoundingBoxView: View {
  let object: DetectedObject
  let rect: CGRect
  
  var body: some View {
    ZStack(alignment: .topLeading) {
      // Bounding box
      Rectangle()
        .stroke(boxColor, lineWidth: 2)
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
      
      // Label background
      Text("\(object.label) \(Int(object.confidence * 100))%")
        .font(.caption2.bold())
        .foregroundColor(.white)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(boxColor)
        .cornerRadius(4)
        .position(x: rect.minX + 40, y: rect.minY - 10)
    }
  }
  
  var boxColor: Color {
    switch object.label.lowercased() {
    case "person": return .green
    case "car", "truck", "bus": return .blue
    case "dog", "cat", "bird": return .orange
    default: return .yellow
    }
  }
}
