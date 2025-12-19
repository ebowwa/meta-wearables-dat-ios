//
//  TrainingOverlay.swift
//  CameraAccess
//
//  Main overlay for object learning - shows library, teach button, and live predictions
//

import SwiftUI

struct TrainingOverlay: View {
    @ObservedObject var trainingService: TrainingService
    
    @State private var showingLearningSession = false
    @State private var showingLibrary = false
    
    let onCapture: (String) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Live prediction display (when we have trained objects)
                if !trainingService.trainedClasses.isEmpty {
                    VStack {
                        // Prediction banner at top
                        if let prediction = trainingService.lastPrediction, prediction.isKnown {
                            PredictionBanner(prediction: prediction)
                                .padding(.top, 60)
                        }
                        Spacer()
                    }
                }
                
                // Bottom controls
                VStack {
                    Spacer()
                    
                    HStack(spacing: 20) {
                        // Object Library button
                        ObjectLibraryButton(
                            objectCount: trainingService.trainedClasses.count,
                            action: { showingLibrary = true }
                        )
                        
                        Spacer()
                        
                        // Teach new object button
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
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100) // Room for existing controls
                }
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
}

// MARK: - Learning Session Overlay (Fullscreen over camera)

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
            // Semi-transparent background
            Color.black.opacity(0.85).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Content
                switch currentStep {
                case .nameObject:
                    NameObjectStep(
                        objectName: $objectName,
                        onContinue: { currentStep = .captureExamples }
                    )
                    
                case .captureExamples:
                    CaptureStep(
                        objectName: objectName,
                        capturedCount: capturedCount,
                        requiredSamples: requiredSamples,
                        isCapturing: isCapturing,
                        onCapture: captureFrame,
                        onFinish: { currentStep = .testRecognition }
                    )
                    
                case .testRecognition:
                    TestStep(
                        objectName: objectName,
                        trainingService: trainingService,
                        onDone: { dismiss() },
                        onRetrain: {
                            capturedCount = 0
                            currentStep = .captureExamples
                        }
                    )
                }
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
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
                
                // Balance spacer
                Color.clear.frame(width: 44, height: 44)
            }
            
            // Progress steps
            HStack(spacing: 4) {
                StepDot(step: 1, label: "Name", isActive: currentStep == .nameObject, isCompleted: currentStep != .nameObject)
                StepLine(isCompleted: currentStep != .nameObject)
                StepDot(step: 2, label: "Show", isActive: currentStep == .captureExamples, isCompleted: currentStep == .testRecognition)
                StepLine(isCompleted: currentStep == .testRecognition)
                StepDot(step: 3, label: "Test", isActive: currentStep == .testRecognition, isCompleted: false)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
        }
    }
    
    private func captureFrame() {
        guard !isCapturing else { return }
        isCapturing = true
        
        // Trigger capture through parent
        onCapture(objectName)
        
        // Simulate success (the actual capture happens in parent)
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                capturedCount += 1
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                isCapturing = false
            }
        }
    }
}

// MARK: - Prediction Banner

struct PredictionBanner: View {
    let prediction: KNNResult
    
    var body: some View {
        HStack(spacing: 12) {
            // Confidence indicator
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

// MARK: - Training Stats (simplified)

struct TrainingStatsView: View {
    @ObservedObject var trainingService: TrainingService
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Statistics") {
                    LabeledContent("Objects", value: "\(trainingService.trainedClasses.count)")
                    LabeledContent("Total Samples", value: "\(trainingService.trainingSamples)")
                }
                
                if !trainingService.trainedClasses.isEmpty {
                    Section("Learned Objects") {
                        ForEach(trainingService.trainedClasses, id: \.self) { label in
                            HStack {
                                Text(label)
                                Spacer()
                                Text("\(trainingService.knn.samplesPerClass[label] ?? 0) samples")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section {
                    Button("Reset All", role: .destructive) {
                        trainingService.resetModel()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Training Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
}

#Preview {
    TrainingOverlay(trainingService: TrainingService()) { _ in }
        .background(Color.gray)
}
