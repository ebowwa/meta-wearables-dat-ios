//
//  TrainingOverlay.swift
//  CameraAccess
//
//  UI for training and inference with on-device KNN
//

import SwiftUI

struct TrainingOverlay: View {
    @ObservedObject var trainingService: TrainingService
    
    @State private var selectedLabel: String = ""
    @State private var customLabel: String = ""
    @State private var showingLabelPicker = false
    @State private var showingStats = false
    @State private var feedbackMessage: String?
    
    let onCapture: (String) -> Void  // Called with label when capture requested
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Mode indicator at top
                VStack {
                    HStack {
                        // Mode toggle
                        Picker("Mode", selection: $trainingService.mode) {
                            Text("Train").tag(TrainingMode.training)
                            Text("Test").tag(TrainingMode.inference)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                        
                        Spacer()
                        
                        // Stats badge
                        Button(action: { showingStats = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "brain.head.profile")
                                Text("\(trainingService.trainingSamples)")
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(15)
                        }
                    }
                    .padding()
                    
                    Spacer()
                }
                
                // Prediction result (inference mode)
                if trainingService.mode == .inference,
                   let prediction = trainingService.lastPrediction {
                    VStack {
                        PredictionBanner(prediction: prediction)
                        Spacer()
                    }
                    .padding(.top, 60)
                }
                
                // Feedback message
                if let message = feedbackMessage {
                    VStack {
                        Spacer()
                        Text(message)
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.green.opacity(0.9))
                            .cornerRadius(10)
                            .padding(.bottom, 160)
                    }
                    .animation(.easeInOut, value: feedbackMessage)
                }
                
                // Bottom controls
                VStack {
                    Spacer()
                    
                    if trainingService.mode == .training {
                        TrainingControls(
                            selectedLabel: $selectedLabel,
                            customLabel: $customLabel,
                            cardLabels: trainingService.cardLabels,
                            onCapture: captureWithLabel
                        )
                    } else {
                        InferenceControls(onPredict: { /* handled by stream */ })
                    }
                }
            }
        }
        .sheet(isPresented: $showingStats) {
            TrainingStatsView(trainingService: trainingService)
        }
    }
    
    private func captureWithLabel() {
        let label = customLabel.isEmpty ? selectedLabel : customLabel
        guard !label.isEmpty else { return }
        
        onCapture(label)
        
        // Show feedback
        feedbackMessage = "Added: \(label)"
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            feedbackMessage = nil
        }
        
        // Clear custom label but keep selected
        customLabel = ""
    }
}

// MARK: - Subviews

struct PredictionBanner: View {
    let prediction: KNNResult
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(prediction.label)
                    .font(.system(size: 36, weight: .bold))
                
                Text("\(Int(prediction.confidence * 100))%")
                    .font(.title2)
                    .foregroundColor(prediction.isKnown ? .green : .orange)
            }
            
            if !prediction.isKnown {
                Text("Unknown - Train this!")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(15)
    }
}

struct TrainingControls: View {
    @Binding var selectedLabel: String
    @Binding var customLabel: String
    let cardLabels: [String]
    let onCapture: () -> Void
    
    @State private var showingPicker = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Quick card buttons (subset)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Show first 13 (hearts) as quick options
                    ForEach(Array(cardLabels.prefix(13)), id: \.self) { label in
                        Button(action: { selectedLabel = label }) {
                            Text(label)
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 44, height: 44)
                                .background(selectedLabel == label ? Color.blue : Color.white.opacity(0.2))
                                .foregroundColor(selectedLabel == label ? .white : .white)
                                .cornerRadius(8)
                        }
                    }
                    
                    // More button
                    Button(action: { showingPicker = true }) {
                        Image(systemName: "ellipsis")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.2))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
            }
            
            // Custom label input
            HStack {
                TextField("Custom label...", text: $customLabel)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                
                // Capture button
                Button(action: onCapture) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                            .frame(width: 65, height: 65)
                        
                        Circle()
                            .fill(canCapture ? Color.blue : Color.gray)
                            .frame(width: 55, height: 55)
                        
                        Image(systemName: "plus")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                }
                .disabled(!canCapture)
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .sheet(isPresented: $showingPicker) {
            CardLabelPicker(labels: cardLabels, selected: $selectedLabel)
        }
    }
    
    private var canCapture: Bool {
        !selectedLabel.isEmpty || !customLabel.isEmpty
    }
}

struct InferenceControls: View {
    let onPredict: () -> Void
    
    var body: some View {
        VStack {
            Text("Point at a card to classify")
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(10)
        }
        .padding(.bottom, 50)
    }
}

struct CardLabelPicker: View {
    let labels: [String]
    @Binding var selected: String
    @Environment(\.dismiss) var dismiss
    
    let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(labels, id: \.self) { label in
                        Button(action: {
                            selected = label
                            dismiss()
                        }) {
                            Text(label)
                                .font(.system(size: 20, weight: .medium))
                                .frame(width: 60, height: 60)
                                .background(suitColor(for: label))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Select Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func suitColor(for label: String) -> Color {
        if label.contains("♥") || label.contains("♦") {
            return .red
        } else {
            return .black
        }
    }
}

struct TrainingStatsView: View {
    @ObservedObject var trainingService: TrainingService
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Model Statistics") {
                    LabeledContent("Total Samples", value: "\(trainingService.trainingSamples)")
                    LabeledContent("Trained Classes", value: "\(trainingService.trainedClasses.count)")
                    LabeledContent("k (neighbors)", value: "\(trainingService.knn.k)")
                }
                
                Section("Samples Per Class") {
                    ForEach(trainingService.trainedClasses, id: \.self) { label in
                        HStack {
                            Text(label)
                                .font(.headline)
                            Spacer()
                            Text("\(trainingService.knn.samplesPerClass[label] ?? 0)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Actions") {
                    Button("Export Model") {
                        shareModel()
                    }
                    
                    Button("Reset Model", role: .destructive) {
                        trainingService.resetModel()
                    }
                }
            }
            .navigationTitle("Training Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func shareModel() {
        let path = trainingService.getModelPath()
        let activityVC = UIActivityViewController(activityItems: [path], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

#Preview {
    TrainingOverlay(trainingService: TrainingService()) { label in
        print("Capture: \(label)")
    }
    .background(Color.black)
}
