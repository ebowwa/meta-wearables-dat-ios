//
//  DataCollectionOverlay.swift
//  CameraAccess
//
//  UI overlay showing YOLO detections and capture controls
//

import SwiftUI

struct DataCollectionOverlay: View {
    @ObservedObject var dataService: DataCollectionService
    
    let detections: [CapturedFrame.Detection]
    let onCapture: () -> Void
    
    @State private var showingStats = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Detection boxes
                ForEach(Array(detections.enumerated()), id: \.offset) { index, detection in
                    DetectionBox(
                        detection: detection,
                        frameSize: geometry.size
                    )
                }
                
                // Controls at bottom
                VStack {
                    Spacer()
                    
                    HStack(spacing: 20) {
                        // Stats button
                        Button(action: { showingStats.toggle() }) {
                            VStack {
                                Image(systemName: "chart.bar.fill")
                                    .font(.title2)
                                Text("\(dataService.capturedCount)")
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(12)
                        }
                        
                        // Capture button
                        Button(action: onCapture) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                                    .frame(width: 70, height: 70)
                                
                                Circle()
                                    .fill(detections.isEmpty ? Color.gray : Color.red)
                                    .frame(width: 58, height: 58)
                                
                                Image(systemName: "camera.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                            }
                        }
                        .disabled(detections.isEmpty)
                        
                        // Auto-capture toggle
                        Button(action: { dataService.autoCapture.toggle() }) {
                            VStack {
                                Image(systemName: dataService.autoCapture ? "bolt.fill" : "bolt.slash")
                                    .font(.title2)
                                Text("Auto")
                                    .font(.caption)
                            }
                            .foregroundColor(dataService.autoCapture ? .yellow : .white)
                            .padding(12)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.bottom, 40)
                }
                
                // Detection count badge
                VStack {
                    HStack {
                        Text("\(detections.count) objects")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(20)
                        Spacer()
                    }
                    .padding()
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showingStats) {
            DatasetStatsView(dataService: dataService)
        }
    }
}

struct DetectionBox: View {
    let detection: CapturedFrame.Detection
    let frameSize: CGSize
    
    private var boxRect: CGRect {
        CGRect(
            x: detection.boundingBox.minX * frameSize.width,
            y: detection.boundingBox.minY * frameSize.height,
            width: detection.boundingBox.width * frameSize.width,
            height: detection.boundingBox.height * frameSize.height
        )
    }
    
    private var boxColor: Color {
        // Color based on class for visual distinction
        let colors: [Color] = [.red, .green, .blue, .orange, .purple, .cyan, .yellow, .pink]
        return colors[detection.classId % colors.count]
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Bounding box
            Rectangle()
                .stroke(boxColor, lineWidth: 2)
                .background(boxColor.opacity(0.1))
                .frame(width: boxRect.width, height: boxRect.height)
                .position(x: boxRect.midX, y: boxRect.midY)
            
            // Label
            Text("\(detection.className) \(Int(detection.confidence * 100))%")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(boxColor)
                .cornerRadius(4)
                .position(x: boxRect.minX + 50, y: boxRect.minY - 10)
        }
    }
}

struct DatasetStatsView: View {
    @ObservedObject var dataService: DataCollectionService
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            let stats = dataService.getDatasetStats()
            
            List {
                Section("Dataset Statistics") {
                    LabeledContent("Images Captured", value: "\(stats.imageCount)")
                    LabeledContent("Total Detections", value: "\(stats.totalDetections)")
                    LabeledContent("Avg per Image", value: stats.imageCount > 0 
                        ? String(format: "%.1f", Double(stats.totalDetections) / Double(stats.imageCount))
                        : "0")
                }
                
                Section("Dataset Location") {
                    Text(dataService.getDatasetPath().path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Actions") {
                    Button("Share Dataset") {
                        shareDataset()
                    }
                    
                    Button("Clear Dataset", role: .destructive) {
                        dataService.clearDataset()
                    }
                }
                
                Section("Auto Capture Settings") {
                    Toggle("Auto Capture", isOn: $dataService.autoCapture)
                    
                    Stepper(
                        "Cooldown: \(Int(dataService.autoCaptureCooldown))s",
                        value: $dataService.autoCaptureCooldown,
                        in: 1...10,
                        step: 1
                    )
                }
            }
            .navigationTitle("Dataset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func shareDataset() {
        let path = dataService.getDatasetPath()
        let activityVC = UIActivityViewController(activityItems: [path], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

#Preview {
    DataCollectionOverlay(
        dataService: DataCollectionService(),
        detections: [
            .init(classId: 0, className: "person", confidence: 0.92, 
                  boundingBox: CGRect(x: 0.2, y: 0.3, width: 0.3, height: 0.5)),
            .init(classId: 56, className: "chair", confidence: 0.78,
                  boundingBox: CGRect(x: 0.6, y: 0.4, width: 0.25, height: 0.4))
        ],
        onCapture: {}
    )
    .background(Color.black)
}
