//
//  DetectionLabelingView.swift
//  CameraAccess
//
//  UI for labeling YOLO detections with custom names and training KNN
//

import SwiftUI

/// View for labeling a single detection with a custom name
struct DetectionLabelingView: View {
    let detection: YOLODetection
    let sourceImage: UIImage
    @ObservedObject var bridge: DetectionTrainingBridge
    
    @State private var customLabel: String = ""
    @State private var showSuccess = false
    @State private var isTraining = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Label Detection")
                .font(.headline)
                .padding(.top)
            
            // Cropped detection preview
            if let croppedImage = bridge.cropDetection(detection, from: sourceImage) {
                Image(uiImage: croppedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .cornerRadius(12)
                    .shadow(radius: 4)
            }
            
            // YOLO detection info
            HStack {
                Text("YOLO detected:")
                    .foregroundColor(.secondary)
                Text(detection.label)
                    .bold()
                Text(String(format: "(%.0f%%)", detection.confidence * 100))
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)
            
            // Custom label input
            VStack(alignment: .leading, spacing: 8) {
                Text("Your label:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextField("e.g., Alice, Bob, My Dog...", text: $customLabel)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal)
            
            // Quick select from trained classes
            if !bridge.trainedClasses.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Existing labels:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(bridge.trainedClasses, id: \.self) { label in
                                Button(label) {
                                    customLabel = label
                                }
                                .buttonStyle(.bordered)
                                .tint(customLabel == label ? .blue : .gray)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            Spacer()
            
            // Train button
            Button(action: trainDetection) {
                HStack {
                    if isTraining {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "brain")
                    }
                    Text(isTraining ? "Training..." : "Train as \"\(customLabel)\"")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(customLabel.isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(customLabel.isEmpty || isTraining)
            .padding(.horizontal)
            
            // Stats
            Text("\(bridge.totalSamples) samples across \(bridge.trainedClasses.count) classes")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom)
        }
        .overlay {
            if showSuccess {
                successOverlay
            }
        }
    }
    
    private var successOverlay: some View {
        VStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            Text("Trained!")
                .font(.title2)
                .bold()
        }
        .padding(40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
    private func trainDetection() {
        isTraining = true
        
        Task {
            let success = await bridge.trainFromDetection(
                detection,
                in: sourceImage,
                withLabel: customLabel
            )
            
            isTraining = false
            
            if success {
                showSuccess = true
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                dismiss()
            }
        }
    }
}

/// View showing KNN prediction overlay on a detection
struct DetectionPredictionBadge: View {
    let prediction: DetectionPrediction
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Custom label from KNN
            if prediction.knnResult.isKnown {
                Text(prediction.knnResult.label)
                    .font(.caption)
                    .bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.8))
                    .cornerRadius(4)
            }
            
            // Original YOLO label
            Text(prediction.detection.label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.5))
                .cornerRadius(3)
        }
    }
}

// MARK: - Preview

#Preview {
    let mockDetection = YOLODetection(
        label: "person",
        confidence: 0.92,
        boundingBox: CGRect(x: 0.2, y: 0.3, width: 0.3, height: 0.4)
    )
    
    // Create a simple test image
    let size = CGSize(width: 640, height: 480)
    let renderer = UIGraphicsImageRenderer(size: size)
    let testImage = renderer.image { ctx in
        UIColor.gray.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
    }
    
    return DetectionLabelingView(
        detection: mockDetection,
        sourceImage: testImage,
        bridge: DetectionTrainingBridge()
    )
}
