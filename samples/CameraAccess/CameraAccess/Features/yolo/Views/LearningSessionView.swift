//
//  LearningSessionView.swift
//  CameraAccess
//
//  Guided 3-step flow for teaching the AI to recognize objects
//

import SwiftUI

/// Learning session states
enum LearningStep {
    case nameObject      // Step 1: Name what you want to teach
    case captureExamples // Step 2: Show examples
    case testRecognition // Step 3: Test it works
}

/// Main container for guided object learning
struct LearningSessionView: View {
    @ObservedObject var trainingService: TrainingService
    @Environment(\.dismiss) var dismiss
    
    @State private var currentStep: LearningStep = .nameObject
    @State private var objectName: String = ""
    @State private var capturedCount: Int = 0
    @State private var isCapturing: Bool = false
    
    let requiredSamples = 5
    let onCaptureFrame: () -> UIImage?  // Get current camera frame
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with progress
                headerView
                
                // Main content area
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
            // Close button
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.7))
                        .padding()
                }
                Spacer()
            }
            
            // Step indicator
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
        .background(Color.black)
    }
    
    private func captureFrame() {
        guard !isCapturing, let image = onCaptureFrame() else { return }
        
        isCapturing = true
        
        Task {
            let success = await trainingService.addTrainingSample(image: image, label: objectName)
            await MainActor.run {
                if success {
                    capturedCount += 1
                    // Haptic feedback
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                }
                isCapturing = false
            }
        }
    }
}

// MARK: - Step Components

struct StepDot: View {
    let step: Int
    let label: String
    let isActive: Bool
    let isCompleted: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.blue : (isCompleted ? Color.green : Color.gray.opacity(0.3)))
                    .frame(width: 32, height: 32)
                
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                } else {
                    Text("\(step)")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                }
            }
            
            Text(label)
                .font(.caption2)
                .foregroundColor(isActive ? .white : .gray)
        }
    }
}

struct StepLine: View {
    let isCompleted: Bool
    
    var body: some View {
        Rectangle()
            .fill(isCompleted ? Color.green : Color.gray.opacity(0.3))
            .frame(height: 2)
            .frame(maxWidth: 40)
    }
}

// MARK: - Step 1: Name Object

struct NameObjectStep: View {
    @Binding var objectName: String
    let onContinue: () -> Void
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon
            Image(systemName: "tag.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            // Title
            VStack(spacing: 8) {
                Text("What do you want to teach me?")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                
                Text("Enter a name for the object")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            // Input
            TextField("e.g., Coffee Mug, Keys, Badge...", text: $objectName)
                .textFieldStyle(.plain)
                .font(.title3)
                .foregroundColor(.white)
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal, 32)
                .focused($isFocused)
                .onSubmit { if canContinue { onContinue() } }
            
            Spacer()
            
            // Continue button
            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canContinue ? Color.blue : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(!canContinue)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .onAppear { isFocused = true }
    }
    
    private var canContinue: Bool {
        !objectName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - Step 2: Capture Examples

struct CaptureStep: View {
    let objectName: String
    let capturedCount: Int
    let requiredSamples: Int
    let isCapturing: Bool
    let onCapture: () -> Void
    let onFinish: () -> Void
    
    private var progress: Double {
        Double(capturedCount) / Double(requiredSamples)
    }
    
    private var canFinish: Bool {
        capturedCount >= requiredSamples
    }
    
    private var hint: String {
        switch capturedCount {
        case 0: return "Point at your \(objectName) and tap capture"
        case 1: return "Great! Now try a slightly different angle"
        case 2: return "Perfect! Try from the other side"
        case 3: return "Almost there! Show it closer"
        case 4: return "One more! Try different lighting"
        default: return "Looking good! Capture more or continue"
        }
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: progress)
                
                VStack {
                    Text("\(capturedCount)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                    Text("of \(requiredSamples)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            // Object name
            Text("Show me your **\(objectName)**")
                .font(.title3)
                .foregroundColor(.white)
            
            // Hint
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text(hint)
                    .font(.subheadline)
            }
            .foregroundColor(.white.opacity(0.8))
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(10)
            .padding(.horizontal)
            
            Spacer()
            
            // Capture button
            Button(action: onCapture) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .fill(isCapturing ? Color.gray : Color.white)
                        .frame(width: 65, height: 65)
                        .scaleEffect(isCapturing ? 0.9 : 1.0)
                        .animation(.easeInOut(duration: 0.1), value: isCapturing)
                }
            }
            .disabled(isCapturing)
            
            // Done button
            if canFinish {
                Button(action: onFinish) {
                    Text("Done - Test It! →")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(10)
                }
                .padding(.top)
            }
            
            Spacer().frame(height: 32)
        }
    }
}

// MARK: - Step 3: Test Recognition

struct TestStep: View {
    let objectName: String
    @ObservedObject var trainingService: TrainingService
    let onDone: () -> Void
    let onRetrain: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Result display
            if let prediction = trainingService.lastPrediction {
                VStack(spacing: 16) {
                    // Match indicator
                    if prediction.label == objectName && prediction.isKnown {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.green)
                        
                        Text("Found your \(objectName)!")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        
                        Text("\(Int(prediction.confidence * 100))% confident")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 80))
                            .foregroundColor(.orange)
                        
                        Text("Seeing: \(prediction.label)")
                            .font(.title2)
                            .foregroundColor(.white)
                        
                        Text("Point at your \(objectName) to test")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    
                    Text("Point at your \(objectName)")
                        .font(.title3)
                        .foregroundColor(.white)
                    
                    Text("I'll try to recognize it")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            // Actions
            VStack(spacing: 12) {
                Button(action: onDone) {
                    Text("Done")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                
                Button(action: onRetrain) {
                    Text("Add More Examples")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }
}
