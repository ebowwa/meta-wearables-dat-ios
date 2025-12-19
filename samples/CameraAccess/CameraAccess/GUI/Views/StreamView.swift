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
            
            // NOTE: DetectionOverlayView was removed here because TrainingOverlay 
            // (below) already renders tappable detection boxes for the same detections.
            // Having both caused duplicate bounding boxes/labels per object.
            // TrainingOverlay is preferred as it supports:
            // - Tap-to-train interactions
            // - KNN prediction labels
            // - Manual bounding box drawing
          }
        }
        .edgesIgnoringSafeArea(.all)
      } else {
        ProgressView()
          .scaleEffect(1.5)
          .foregroundColor(.white)
      }
      
      // Detection stats (top-left)
      if viewModel.isDetectionEnabled {
        VStack {
          HStack {
            DetectionStatsView(
              inferenceTimeMs: viewModel.detectionService.inferenceTimeMs,
              detectionCount: viewModel.currentDetections.count,
              modelName: viewModel.modelManager.activeModel?.name
            )
            Spacer()
          }
          .padding()
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
      
      // Training overlay - always visible during streaming
      GeometryReader { geometry in
        TrainingOverlay(
          trainingService: viewModel.trainingService,
          detections: viewModel.currentDetections,
          currentFrame: viewModel.currentVideoFrame,
          viewSize: geometry.size,
          detectionPredictions: viewModel.detectionPredictions
        ) { label, boundingBox in
          viewModel.captureWithLabel(label, boundingBox: boundingBox)
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
    // Photo training workflow - primary path for camera button
    // Shows high-res photo with YOLO detections, allows tap-to-train
    .sheet(isPresented: $viewModel.showPhotoTraining) {
      if let photo = viewModel.photoForTraining {
        PhotoTrainingView(
          photo: photo,
          detections: viewModel.photoDetections,
          trainingService: viewModel.trainingService,
          onDismiss: {
            viewModel.dismissPhotoTraining()
          },
          onSaveToPhotos: {
            viewModel.savePhotoToLibrary()
          }
        )
      }
    }
    // Legacy photo preview (share sheet only) - can be triggered programmatically
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
    // Model picker sheet
    .sheet(isPresented: $viewModel.showModelPicker) {
      ModelPickerView(modelManager: viewModel.modelManager)
    }
  }
}

// Extracted controls for clarity
struct ControlsView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @State private var showResetConfirmation = false
  
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

      // Reset training button (only shows if there's training data)
      if viewModel.trainingService.trainingSamples > 0 {
        CircleButton(
          icon: "trash.fill",
          text: nil,
          backgroundColor: .red.opacity(0.8),
          foregroundColor: .white
        ) {
          showResetConfirmation = true
        }
        .alert("Reset Training Data?", isPresented: $showResetConfirmation) {
          Button("Cancel", role: .cancel) { }
          Button("Reset", role: .destructive) {
            viewModel.trainingService.resetModel()
          }
        } message: {
          Text("This will delete all \(viewModel.trainingService.trainingSamples) training samples. This cannot be undone.")
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
      CircleButton(
        icon: "camera.fill",
        text: nil,
        isDisabled: viewModel.streamingStatus != .streaming
      ) {
        viewModel.capturePhoto()
      }
    }
  }
}

