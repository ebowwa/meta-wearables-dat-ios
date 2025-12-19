//
//  TrainingOverlay.swift
//  CameraAccess
//
//  Object learning overlay - uses YOLO detections from glasses stream
//  User taps on detected objects to train them
//

import SwiftUI

struct TrainingOverlay: View {
    @ObservedObject var trainingService: TrainingService
    
    @State private var showingLearningSession = false
    @State private var showingLibrary = false
    @State private var selectedDetection: YOLODetection? = nil
    @State private var labelForDetection: String = ""
    
    // From parent - YOLO detections and current frame
    var detections: [YOLODetection] = []
    var currentFrame: UIImage? = nil
    
    let onCapture: (String) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Tappable detection boxes - user selects what to train
                ForEach(detections) { detection in
                    TappableDetectionBox(
                        detection: detection,
                        frame: detection.boundingBox(in: geometry.size),
                        isSelected: selectedDetection?.id == detection.id,
                        onTap: { selectDetection(detection) }
                    )
                }
                
                // Live prediction display (when we have trained objects)
                if !trainingService.trainedClasses.isEmpty,
                   let prediction = trainingService.lastPrediction,
                   prediction.isKnown {
                    VStack {
                        PredictionBanner(prediction: prediction)
                            .padding(.top, 60)
                        Spacer()
                    }
                }
                
                // Bottom controls
                VStack {
                    Spacer()
                    
                    // Selection prompt
                    if selectedDetection != nil {
                        LabelInputBar(
                            detection: selectedDetection!,
                            label: $labelForDetection,
                            onConfirm: confirmTraining,
                            onCancel: { selectedDetection = nil; labelForDetection = "" }
                        )
                    } else {
                        // Main action bar
                        HStack(spacing: 20) {
                            // Inventory button
                            ObjectLibraryButton(
                                objectCount: trainingService.trainedClasses.count,
                                action: { showingLibrary = true }
                            )
                            
                            Spacer()
                            
                            // Instructions or teach button
                            if detections.isEmpty {
                                // No detections - show teach button for manual mode
                                Button(action: { showingLearningSession = true }) {
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
                            } else {
                                // Has detections - prompt to tap
                                Text("Tap an object to teach me")
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
                .padding(.bottom, 100)
            }
        }
        .fullScreenCover(isPresented: $showingLearningSession) {
            LearningSessionOverlay(
                trainingService: trainingService,
                onCapture: onCapture
            )
        }
        .sheet(isPresented: $showingLibrary) {
            ObjectLibraryView(trainingService: trainingService)
        }
    }
    
    private func selectDetection(_ detection: YOLODetection) {
        selectedDetection = detection
        // Pre-fill with YOLO label if we don't already know it
        if !trainingService.trainedClasses.contains(detection.label) {
            labelForDetection = detection.label
        } else {
            labelForDetection = ""
        }
        
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
    
    private func confirmTraining() {
        guard !labelForDetection.isEmpty else { return }
        
        // Use the label that user entered/confirmed
        onCapture(labelForDetection)
        
        // Reset
        selectedDetection = nil
        labelForDetection = ""
        
        // Success haptic
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)
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
            // Bounding box
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.yellow : Color.green, lineWidth: isSelected ? 3 : 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.yellow.opacity(0.2) : Color.clear)
                )
                .frame(width: frame.width, height: frame.height)
            
            // Label
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
            // Header
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
            
            // Input row
            HStack(spacing: 12) {
                TextField("e.g., Coffee Mug", text: $label)
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
            
            Text("YOLO detected: \(detection.label)")
                .font(.caption)
                .foregroundColor(.gray)
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
                .fill(prediction.isKnown ? Color.green : Color.orange)
                .frame(width: 12, height: 12)
            
            Text(prediction.label)
                .font(.title2.bold())
                .foregroundColor(.white)
            
            Text("\(Int(prediction.confidence * 100))%")
                .font(.subheadline)
                .foregroundColor(prediction.isKnown ? .green : .orange)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(25)
    }
}

// MARK: - Learning Session (fallback for no detections)

struct LearningSessionOverlay: View {
    @ObservedObject var trainingService: TrainingService
    @Environment(\.dismiss) var dismiss
    
    @State private var currentStep: LearningStep = .nameObject
    @State private var objectName: String = ""
    @State private var capturedCount: Int = 0
    @State private var isCapturing: Bool = false
    
    let requiredSamples = 5
    let onCapture: (String) -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.7))
                            .padding()
                    }
                    Spacer()
                    Text("Teach Me")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                
                // Steps
                HStack(spacing: 4) {
                    StepDot(step: 1, label: "Name", isActive: currentStep == .nameObject, isCompleted: currentStep != .nameObject)
                    StepLine(isCompleted: currentStep != .nameObject)
                    StepDot(step: 2, label: "Show", isActive: currentStep == .captureExamples, isCompleted: currentStep == .testRecognition)
                    StepLine(isCompleted: currentStep == .testRecognition)
                    StepDot(step: 3, label: "Test", isActive: currentStep == .testRecognition, isCompleted: false)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
                
                // Content
                switch currentStep {
                case .nameObject:
                    NameObjectStep(objectName: $objectName, onContinue: { currentStep = .captureExamples })
                case .captureExamples:
                    CaptureStep(objectName: objectName, capturedCount: capturedCount, requiredSamples: requiredSamples, isCapturing: isCapturing, onCapture: {
                        onCapture(objectName)
                        capturedCount += 1
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                    }, onFinish: { currentStep = .testRecognition })
                case .testRecognition:
                    TestStep(objectName: objectName, trainingService: trainingService, onDone: { dismiss() }, onRetrain: { capturedCount = 0; currentStep = .captureExamples })
                }
            }
        }
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
