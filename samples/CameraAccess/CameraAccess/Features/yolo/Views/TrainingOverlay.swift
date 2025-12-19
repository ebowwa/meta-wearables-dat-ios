//
//  TrainingOverlay.swift
//  CameraAccess
//
//  Training UI that overlays on glasses live stream
//  - Tap YOLO detections to train them
//  - Draw bounding box manually when YOLO doesn't detect
//

import SwiftUI

struct TrainingOverlay: View {
    @ObservedObject var trainingService: TrainingService
    
    @State private var showingLibrary = false
    @State private var selectedDetection: YOLODetection? = nil
    @State private var labelForDetection: String = ""
    
    // Manual bounding box drawing
    @State private var isDrawingBox = false
    @State private var boxStart: CGPoint = .zero
    @State private var boxEnd: CGPoint = .zero
    @State private var drawnBox: CGRect? = nil
    @State private var manualLabel: String = ""
    
    // From parent - YOLO detections from glasses stream
    var detections: [YOLODetection] = []
    var currentFrame: UIImage? = nil
    
    let onCapture: (String) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Drag gesture layer for drawing bounding box
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onChanged { value in
                                if !isDrawingBox {
                                    isDrawingBox = true
                                    boxStart = value.startLocation
                                    selectedDetection = nil
                                }
                                boxEnd = value.location
                            }
                            .onEnded { value in
                                let rect = CGRect(
                                    x: min(boxStart.x, boxEnd.x),
                                    y: min(boxStart.y, boxEnd.y),
                                    width: abs(boxEnd.x - boxStart.x),
                                    height: abs(boxEnd.y - boxStart.y)
                                )
                                // Only keep if box is big enough
                                if rect.width > 50 && rect.height > 50 {
                                    drawnBox = rect
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                }
                                isDrawingBox = false
                            }
                    )
                
                // Drawing box preview
                if isDrawingBox {
                    let rect = CGRect(
                        x: min(boxStart.x, boxEnd.x),
                        y: min(boxStart.y, boxEnd.y),
                        width: abs(boxEnd.x - boxStart.x),
                        height: abs(boxEnd.y - boxStart.y)
                    )
                    Rectangle()
                        .stroke(Color.yellow, lineWidth: 3)
                        .background(Color.yellow.opacity(0.1))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                
                // Drawn box (after drag ends)
                if let box = drawnBox {
                    ZStack {
                        Rectangle()
                            .stroke(Color.green, lineWidth: 3)
                            .background(Color.green.opacity(0.15))
                            .frame(width: box.width, height: box.height)
                        
                        // Corners
                        ForEach(0..<4) { i in
                            Circle()
                                .fill(Color.green)
                                .frame(width: 12, height: 12)
                                .position(
                                    x: i % 2 == 0 ? 0 : box.width,
                                    y: i < 2 ? 0 : box.height
                                )
                        }
                    }
                    .frame(width: box.width, height: box.height)
                    .position(x: box.midX, y: box.midY)
                }
                
                // YOLO detection boxes (tappable)
                ForEach(detections) { detection in
                    TappableDetectionBox(
                        detection: detection,
                        frame: detection.boundingBox(in: geometry.size),
                        isSelected: selectedDetection?.id == detection.id,
                        onTap: { 
                            drawnBox = nil  // Clear manual box
                            selectDetection(detection) 
                        }
                    )
                }
                
                // Live prediction banner
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
                    
                    if drawnBox != nil {
                        // Manual box drawn - get label
                        ManualBoxInputBar(
                            label: $manualLabel,
                            onConfirm: confirmManualBox,
                            onCancel: { drawnBox = nil; manualLabel = "" }
                        )
                    } else if let detection = selectedDetection {
                        // YOLO detection selected - name it
                        LabelInputBar(
                            detection: detection,
                            label: $labelForDetection,
                            onConfirm: confirmTraining,
                            onCancel: { selectedDetection = nil; labelForDetection = "" }
                        )
                    } else {
                        // Main action bar with hint
                        ActionBar(
                            objectCount: trainingService.trainedClasses.count,
                            hasDetections: !detections.isEmpty,
                            onInventory: { showingLibrary = true }
                        )
                    }
                }
                .padding(.bottom, 100)
                
                // Draw hint (top)
                if drawnBox == nil && selectedDetection == nil && detections.isEmpty {
                    VStack {
                        HStack {
                            Spacer()
                            Text("Draw a box around the object")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.8))
                                .cornerRadius(8)
                            Spacer()
                        }
                        .padding(.top, 120)
                        Spacer()
                    }
                }
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
    
    private func confirmManualBox() {
        guard !manualLabel.isEmpty else { return }
        onCapture(manualLabel)
        drawnBox = nil
        manualLabel = ""
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Action Bar

struct ActionBar: View {
    let objectCount: Int
    let hasDetections: Bool
    let onInventory: () -> Void
    
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
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Manual Box Input Bar

struct ManualBoxInputBar: View {
    @Binding var label: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Name this object:")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
            
            HStack(spacing: 12) {
                TextField("e.g., Coffee Cup, Badge...", text: $label)
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

// MARK: - Label Input Bar (for YOLO detections)

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
