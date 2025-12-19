/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// PhotoTrainingView.swift
//
// Training UI for high-resolution photos captured from Meta glasses.
// Allows users to tap YOLO detections or draw manual boxes to train KNN.
//
// WORKFLOW:
// 1. Camera button triggers high-res photo capture via DAT SDK
// 2. YOLO runs on the photo to detect objects
// 3. This view displays photo with tappable detection overlays
// 4. User taps detection → enters custom label → KNN trains on cropped region
//
// WHY HIGH-RES PHOTOS FOR TRAINING:
// - Video frames are low resolution (optimized for streaming bandwidth)
// - Photos use native sensor resolution for maximum detail
// - Better image quality → better embeddings → more accurate KNN predictions
// - Users expect "camera button" to capture something meaningful
//

import SwiftUI

struct PhotoTrainingView: View {
    let photo: UIImage
    let detections: [YOLODetection]
    let trainingService: TrainingService
    let onDismiss: () -> Void
    let onSaveToPhotos: (() -> Void)?
    
    @State private var selectedDetection: YOLODetection?
    @State private var labelText: String = ""
    @State private var showLabelInput: Bool = false
    @State private var isProcessing: Bool = false
    @State private var trainingSuccess: String?
    @State private var dragOffset = CGSize.zero
    
    // Manual box drawing
    @State private var isDrawingBox: Bool = false
    @State private var boxStart: CGPoint = .zero
    @State private var boxEnd: CGPoint = .zero
    @State private var drawnBox: CGRect?
    @State private var manualLabel: String = ""
    
    init(
        photo: UIImage,
        detections: [YOLODetection],
        trainingService: TrainingService,
        onDismiss: @escaping () -> Void,
        onSaveToPhotos: (() -> Void)? = nil
    ) {
        self.photo = photo
        self.detections = detections
        self.trainingService = trainingService
        self.onDismiss = onDismiss
        self.onSaveToPhotos = onSaveToPhotos
    }
    
    var body: some View {
        ZStack {
            // Dark background
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                header
                
                // Photo with detections
                GeometryReader { geometry in
                    ZStack {
                        // Photo
                        Image(uiImage: photo)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                        
                        // Detection overlays
                        detectionOverlays(in: geometry.size)
                        
                        // Manual drawing layer
                        manualDrawingLayer(in: geometry.size)
                        
                        // Drawn box (after drag ends)
                        if let box = drawnBox {
                            drawnBoxOverlay(box: box)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Bottom controls
                bottomControls
            }
            
            // Label input sheet
            if showLabelInput {
                labelInputOverlay
            }
            
            // Success toast
            if let success = trainingSuccess {
                successToast(message: success)
            }
            
            // Processing indicator
            if isProcessing {
                processingOverlay
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    if abs(value.translation.height) > 150 {
                        onDismiss()
                    } else {
                        withAnimation(.spring()) {
                            dragOffset = .zero
                        }
                    }
                }
        )
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Button("Cancel") {
                onDismiss()
            }
            .foregroundColor(.white)
            
            Spacer()
            
            Text("Train on Photo")
                .font(.headline)
                .foregroundColor(.white)
            
            Spacer()
            
            if let onSave = onSaveToPhotos {
                Button {
                    onSave()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundColor(.white)
                }
            } else {
                // Spacer for alignment
                Image(systemName: "square.and.arrow.down")
                    .foregroundColor(.clear)
            }
        }
        .padding()
        .background(Color.black.opacity(0.5))
    }
    
    // MARK: - Detection Overlays
    
    private func detectionOverlays(in size: CGSize) -> some View {
        ForEach(detections) { detection in
            let frame = detection.boundingBox(in: size)
            
            Button {
                selectDetection(detection)
            } label: {
                ZStack(alignment: .topLeading) {
                    // Bounding box
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(selectedDetection?.id == detection.id ? Color.green : Color.blue, lineWidth: 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.blue.opacity(0.15))
                        )
                    
                    // Label badge
                    Text(detection.label)
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(4)
                        .offset(x: 4, y: 4)
                }
            }
            .buttonStyle(.plain)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
        }
    }
    
    // MARK: - Manual Drawing
    
    private func manualDrawingLayer(in size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .allowsHitTesting(detections.isEmpty && drawnBox == nil)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        if !isDrawingBox {
                            isDrawingBox = true
                            boxStart = value.startLocation
                        }
                        boxEnd = value.location
                    }
                    .onEnded { _ in
                        if isDrawingBox {
                            let rect = CGRect(
                                x: min(boxStart.x, boxEnd.x),
                                y: min(boxStart.y, boxEnd.y),
                                width: abs(boxEnd.x - boxStart.x),
                                height: abs(boxEnd.y - boxStart.y)
                            )
                            if rect.width > 30 && rect.height > 30 {
                                drawnBox = rect
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                        }
                        isDrawingBox = false
                    }
            )
            .overlay {
                // Drawing preview
                if isDrawingBox {
                    let rect = CGRect(
                        x: min(boxStart.x, boxEnd.x),
                        y: min(boxStart.y, boxEnd.y),
                        width: abs(boxEnd.x - boxStart.x),
                        height: abs(boxEnd.y - boxStart.y)
                    )
                    Rectangle()
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                        .background(Color.orange.opacity(0.1))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
    }
    
    private func drawnBoxOverlay(box: CGRect) -> some View {
        ZStack {
            Rectangle()
                .stroke(Color.green, lineWidth: 3)
                .background(Color.green.opacity(0.15))
            
            // Input field inside box
            VStack {
                TextField("Label this object", text: $manualLabel)
                    .textFieldStyle(.roundedBorder)
                    .padding(8)
                
                HStack(spacing: 12) {
                    Button {
                        drawnBox = nil
                        manualLabel = ""
                    } label: {
                        Text("Clear")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(8)
                    }
                    
                    Button {
                        trainManualBox(box)
                    } label: {
                        Text("Train ✓")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(manualLabel.isEmpty ? Color.gray : Color.green)
                            .cornerRadius(8)
                    }
                    .disabled(manualLabel.isEmpty)
                }
            }
            .padding(8)
        }
        .frame(width: box.width, height: max(box.height, 100))
        .position(x: box.midX, y: box.midY)
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControls: some View {
        VStack(spacing: 12) {
            // Stats
            HStack {
                Image(systemName: "brain")
                Text("\(trainingService.trainingSamples) samples")
                Text("•")
                Text("\(trainingService.trainedClasses.count) classes")
            }
            .font(.caption)
            .foregroundColor(.white.opacity(0.7))
            
            // Hints
            if detections.isEmpty && drawnBox == nil {
                Text("No objects detected. Draw a box around an object to train.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else if !detections.isEmpty && selectedDetection == nil {
                Text("Tap a detection to label it")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color.black.opacity(0.5))
    }
    
    // MARK: - Label Input Overlay
    
    private var labelInputOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    cancelLabelInput()
                }
            
            VStack(spacing: 16) {
                // Header with detection info
                if let detection = selectedDetection {
                    Text("Label this \"\(detection.label)\"")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                
                // Existing classes as suggestions
                if !trainingService.trainedClasses.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(trainingService.trainedClasses, id: \.self) { label in
                                Button {
                                    labelText = label
                                } label: {
                                    Text(label)
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(labelText == label ? Color.green : Color.blue.opacity(0.8))
                                        .cornerRadius(16)
                                }
                            }
                        }
                    }
                }
                
                // Text field
                TextField("Enter label (e.g., Alice, My Dog)", text: $labelText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                
                // Buttons
                HStack(spacing: 20) {
                    Button {
                        cancelLabelInput()
                    } label: {
                        Text("Cancel")
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.gray.opacity(0.5))
                            .cornerRadius(12)
                    }
                    
                    Button {
                        trainSelectedDetection()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Train")
                        }
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(labelText.isEmpty ? Color.gray : Color.green)
                        .cornerRadius(12)
                    }
                    .disabled(labelText.isEmpty)
                }
            }
            .padding(24)
            .background(Color.black.opacity(0.9))
            .cornerRadius(20)
            .padding(40)
        }
    }
    
    // MARK: - Success Toast
    
    private func successToast(message: String) -> some View {
        VStack {
            Spacer()
            
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(message)
                    .foregroundColor(.white)
            }
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(12)
            .padding(.bottom, 100)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // MARK: - Processing Overlay
    
    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("Training...")
                    .foregroundColor(.white)
            }
            .padding(40)
            .background(Color.black.opacity(0.8))
            .cornerRadius(20)
        }
    }
    
    // MARK: - Actions
    
    private func selectDetection(_ detection: YOLODetection) {
        selectedDetection = detection
        labelText = ""  // Start fresh, don't use YOLO label
        showLabelInput = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func cancelLabelInput() {
        showLabelInput = false
        selectedDetection = nil
        labelText = ""
    }
    
    private func trainSelectedDetection() {
        guard let detection = selectedDetection, !labelText.isEmpty else { return }
        
        isProcessing = true
        showLabelInput = false
        
        Task {
            let success = await trainingService.addTrainingSample(
                image: photo,
                boundingBox: detection.boundingBox,
                label: labelText
            )
            
            isProcessing = false
            
            if success {
                let samples = trainingService.knn.samplesPerClass[labelText] ?? 1
                showSuccessToast("Trained '\(labelText)' (\(samples) sample\(samples > 1 ? "s" : ""))")
            }
            
            selectedDetection = nil
            labelText = ""
        }
    }
    
    private func trainManualBox(_ box: CGRect) {
        guard !manualLabel.isEmpty else { return }
        
        isProcessing = true
        
        // Convert screen box to normalized Vision coordinates
        // This is approximate - for full accuracy we'd need the image frame
        Task {
            // Simple normalization (assumes box is in image space)
            let imageSize = photo.size
            let normalizedBox = CGRect(
                x: box.origin.x / imageSize.width,
                y: 1 - (box.origin.y / imageSize.height) - (box.height / imageSize.height),
                width: box.width / imageSize.width,
                height: box.height / imageSize.height
            )
            
            let success = await trainingService.addTrainingSample(
                image: photo,
                boundingBox: normalizedBox,
                label: manualLabel
            )
            
            isProcessing = false
            
            if success {
                let samples = trainingService.knn.samplesPerClass[manualLabel] ?? 1
                showSuccessToast("Trained '\(manualLabel)' (\(samples) sample\(samples > 1 ? "s" : ""))")
                drawnBox = nil
                manualLabel = ""
            }
        }
    }
    
    private func showSuccessToast(_ message: String) {
        withAnimation {
            trainingSuccess = message
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation {
                trainingSuccess = nil
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PhotoTrainingView(
        photo: UIImage(systemName: "photo")!,
        detections: [],
        trainingService: TrainingService(),
        onDismiss: {}
    )
}
