//
//  TrainingOverlay.swift
//  CameraAccess
//
//  Minimal UI for training and inference with on-device KNN
//

import SwiftUI

struct TrainingOverlay: View {
    @ObservedObject var trainingService: TrainingService
    
    @State private var labelInput: String = ""
    @State private var feedbackMessage: String?
    @State private var showingStats = false
    
    let onCapture: (String) -> Void
    
    var body: some View {
        ZStack {
            // Train mode: minimal input at bottom
            if trainingService.mode == .training {
                VStack {
                    Spacer()
                    
                    // Simple capture bar
                    HStack(spacing: 12) {
                        // Label input
                        TextField("Label...", text: $labelInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        
                        // Capture button
                        Button(action: capture) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(labelInput.isEmpty ? .gray : .blue)
                        }
                        .disabled(labelInput.isEmpty)
                        
                        // Mode toggle
                        Button(action: { trainingService.mode = .inference }) {
                            Image(systemName: "play.circle")
                                .font(.system(size: 32))
                                .foregroundColor(.green)
                        }
                        
                        // Stats
                        Button(action: { showingStats = true }) {
                            Text("\(trainingService.trainingSamples)")
                                .font(.caption.bold())
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
            
            // Test mode: prediction display
            if trainingService.mode == .inference {
                VStack {
                    // Prediction result
                    if let prediction = trainingService.lastPrediction {
                        HStack {
                            Text(prediction.label)
                                .font(.system(size: 32, weight: .bold))
                            Text("\(Int(prediction.confidence * 100))%")
                                .foregroundColor(prediction.isKnown ? .green : .orange)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                    }
                    
                    Spacer()
                    
                    // Back to train
                    Button(action: { trainingService.mode = .training }) {
                        HStack {
                            Image(systemName: "pencil")
                            Text("Train")
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                    }
                    .padding(.bottom)
                }
                .padding(.top, 50)
            }
            
            // Feedback toast
            if let message = feedbackMessage {
                VStack {
                    Text(message)
                        .padding(8)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    Spacer()
                }
                .padding(.top, 100)
            }
        }
        .sheet(isPresented: $showingStats) {
            TrainingStatsView(trainingService: trainingService)
        }
    }
    
    private func capture() {
        guard !labelInput.isEmpty else { return }
        onCapture(labelInput)
        feedbackMessage = "✓ \(labelInput)"
        let captured = labelInput
        labelInput = ""
        
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if feedbackMessage == "✓ \(captured)" {
                feedbackMessage = nil
            }
        }
    }
}

struct TrainingStatsView: View {
    @ObservedObject var trainingService: TrainingService
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Stats") {
                    LabeledContent("Samples", value: "\(trainingService.trainingSamples)")
                    LabeledContent("Classes", value: "\(trainingService.trainedClasses.count)")
                }
                
                if !trainingService.trainedClasses.isEmpty {
                    Section("Classes") {
                        ForEach(trainingService.trainedClasses, id: \.self) { label in
                            HStack {
                                Text(label)
                                Spacer()
                                Text("\(trainingService.knn.samplesPerClass[label] ?? 0)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section {
                    Button("Reset", role: .destructive) {
                        trainingService.resetModel()
                    }
                }
            }
            .navigationTitle("Training")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
}

#Preview {
    TrainingOverlay(trainingService: TrainingService()) { _ in }
        .background(Color.black)
}
