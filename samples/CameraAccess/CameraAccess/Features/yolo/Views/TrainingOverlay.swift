//
//  TrainingOverlay.swift
//  CameraAccess
//
//  Training UI that overlays DIRECTLY on glasses live stream
//  NO separate views - everything happens on top of the camera feed
//

import SwiftUI

struct TrainingOverlay: View {
    @ObservedObject var trainingService: TrainingService
    
    @State private var showingLibrary = false
    @State private var selectedDetection: YOLODetection? = nil
    @State private var labelForDetection: String = ""
    @State private var isInManualMode = false
    @State private var manualLabel: String = ""
    @State private var manualCaptureCount: Int = 0
    
    // From parent - YOLO detections from glasses stream
    var detections: [YOLODetection] = []
    var currentFrame: UIImage? = nil
    
    let onCapture: (String) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Tappable YOLO detection boxes on glasses stream
                ForEach(detections) { detection in
                    TappableDetectionBox(
                        detection: detection,
                        frame: detection.boundingBox(in: geometry.size),
                        isSelected: selectedDetection?.id == detection.id,
                        onTap: { selectDetection(detection) }
                    )
                }
                
                // Live prediction (when trained objects exist)
                if !trainingService.trainedClasses.isEmpty,
                   let prediction = trainingService.lastPrediction,
                   prediction.isKnown {
                    VStack {
                        PredictionBanner(prediction: prediction)
                            .padding(.top, 60)
                        Spacer()
                    }
                }
                
                // Bottom UI
                VStack {
                    Spacer()
                    
                    if isInManualMode {
                        // Manual capture mode (no YOLO needed)
                        ManualCaptureBar(
                            label: $manualLabel,
                            captureCount: manualCaptureCount,
                            onCapture: manualCapture,
                            onDone: exitManualMode
                        )
                    } else if let detection = selectedDetection {
                        // Detection selected - name it
                        LabelInputBar(
                            detection: detection,
                            label: $labelForDetection,
                            onConfirm: confirmTraining,
                            onCancel: { selectedDetection = nil; labelForDetection = "" }
                        )
                    } else {
                        // Main action bar
                        ActionBar(
                            objectCount: trainingService.trainedClasses.count,
                            hasDetections: !detections.isEmpty,
                            onInventory: { showingLibrary = true },
                            onManualMode: { isInManualMode = true }
                        )
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .sheet(isPresented: $showingLibrary) {
            ObjectLibraryView(trainingService: trainingService)
        }
    }
    
    private func selectDetection(_ detection: YOLODetection) {
        selectedDetection = detection
        labelForDetection = detection.label
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func confirmTraining() {
        guard !labelForDetection.isEmpty else { return }
        onCapture(labelForDetection)
        selectedDetection = nil
        labelForDetection = ""
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    
    private func manualCapture() {
        guard !manualLabel.isEmpty else { return }
        onCapture(manualLabel)
        manualCaptureCount += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    private func exitManualMode() {
        isInManualMode = false
        manualLabel = ""
        manualCaptureCount = 0
    }
}

// MARK: - Action Bar

struct ActionBar: View {
    let objectCount: Int
    let hasDetections: Bool
    let onInventory: () -> Void
    let onManualMode: () -> Void
    
    var body: some View {
        HStack(spacing: 20) {
            // Inventory
            ObjectLibraryButton(objectCount: objectCount, action: onInventory)
            
            Spacer()
            
            if hasDetections {
                Text("Tap object to teach")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
            } else {
                // Manual mode button
                Button(action: onManualMode) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Teach")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(25)
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Manual Capture Bar

struct ManualCaptureBar: View {
    @Binding var label: String
    let captureCount: Int
    let onCapture: () -> Void
    let onDone: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Point at object, then capture")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Spacer()
                if captureCount >= 3 {
                    Button("Done ✓", action: onDone)
                        .font(.headline)
                        .foregroundColor(.green)
                }
            }
            
            // Input + capture
            HStack(spacing: 12) {
                TextField("Object name...", text: $label)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                
                // Capture button
                Button(action: onCapture) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                            .frame(width: 60, height: 60)
                        Circle()
                            .fill(label.isEmpty ? Color.gray : Color.blue)
                            .frame(width: 50, height: 50)
                        
                        if captureCount > 0 {
                            Text("\(captureCount)")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: "plus")
                                .foregroundColor(.white)
                        }
                    }
                }
                .disabled(label.isEmpty)
            }
            
            // Progress hint
            if captureCount > 0 && captureCount < 5 {
                Text("\(captureCount)/5 samples (need at least 3)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

// MARK: - Tappable Detection Box

struct TappableDetectionBox: View {
    let detection: YOLODetection
    let frame: CGRect
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.yellow : Color.green, lineWidth: isSelected ? 3 : 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.yellow.opacity(0.2) : Color.clear)
                )
                .frame(width: frame.width, height: frame.height)
            
            VStack {
                Text(detection.label)
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.yellow : Color.green)
                    .cornerRadius(4)
                Spacer()
            }
            .frame(width: frame.width, height: frame.height, alignment: .top)
            .offset(y: -20)
        }
        .position(x: frame.midX, y: frame.midY)
        .onTapGesture { onTap() }
    }
}

// MARK: - Label Input Bar

struct LabelInputBar: View {
    let detection: YOLODetection
    @Binding var label: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Name this \(detection.label):")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
            
            HStack(spacing: 12) {
                TextField("e.g., My Coffee Mug", text: $label)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                
                Button(action: onConfirm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(label.isEmpty ? .gray : .green)
                }
                .disabled(label.isEmpty)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

// MARK: - Prediction Banner

struct PredictionBanner: View {
    let prediction: KNNResult
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.green)
                .frame(width: 12, height: 12)
            
            Text(prediction.label)
                .font(.title2.bold())
                .foregroundColor(.white)
            
            Text("\(Int(prediction.confidence * 100))%")
                .font(.subheadline)
                .foregroundColor(.green)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(25)
    }
}

// MARK: - Training Stats

struct TrainingStatsView: View {
    @ObservedObject var trainingService: TrainingService
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Stats") {
                    LabeledContent("Objects", value: "\(trainingService.trainedClasses.count)")
                    LabeledContent("Samples", value: "\(trainingService.trainingSamples)")
                }
                Section {
                    Button("Reset All", role: .destructive) {
                        trainingService.resetModel()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Training")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

#Preview {
    TrainingOverlay(trainingService: TrainingService()) { _ in }
        .background(Color.gray)
}
