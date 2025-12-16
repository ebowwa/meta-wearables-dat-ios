/*
 * DetectionOverlayView.swift
 * CameraAccess
 *
 * Generic overlay for displaying YOLO detection bounding boxes.
 * Works with any YOLO model version.
 */

import SwiftUI

struct DetectionOverlayView: View {
    let detections: [YOLODetection]
    let viewSize: CGSize
    
    var body: some View {
        ZStack {
            ForEach(detections) { detection in
                DetectionBoxView(
                    detection: detection,
                    frame: detection.boundingBox(in: viewSize)
                )
            }
        }
    }
}

struct DetectionBoxView: View {
    let detection: YOLODetection
    let frame: CGRect
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Bounding box
            Rectangle()
                .stroke(boxColor, lineWidth: 2)
                .frame(width: frame.width, height: frame.height)
            
            // Label background
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(detection.label)
                        .font(.caption2)
                        .fontWeight(.semibold)
                    
                    Text("\(Int(detection.confidence * 100))%")
                        .font(.caption2)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(boxColor)
                .foregroundColor(.white)
            }
            .offset(y: -20)
        }
        .position(x: frame.midX, y: frame.midY)
    }
    
    private var boxColor: Color {
        // Color-code by object category for visual distinction
        let label = detection.label.lowercased()
        
        if label.contains("person") || label.contains("face") {
            return .green
        } else if label.contains("car") || label.contains("truck") || label.contains("bus") || label.contains("vehicle") {
            return .blue
        } else if label.contains("dog") || label.contains("cat") || label.contains("bird") || label.contains("animal") {
            return .orange
        } else if label.contains("card") || label.contains("poker") {
            return .red
        } else {
            return .purple
        }
    }
}

// MARK: - Detection Stats Overlay

struct DetectionStatsView: View {
    let inferenceTimeMs: Double
    let detectionCount: Int
    let modelName: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let name = modelName {
                Text("Model: \(name)")
                    .font(.caption2)
            }
            Text("Inference: \(String(format: "%.1f", inferenceTimeMs))ms")
                .font(.caption2)
            Text("Objects: \(detectionCount)")
                .font(.caption2)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

#Preview {
    ZStack {
        Color.gray
        DetectionOverlayView(
            detections: [
                YOLODetection(label: "person", confidence: 0.95, boundingBox: CGRect(x: 0.2, y: 0.3, width: 0.3, height: 0.5)),
                YOLODetection(label: "car", confidence: 0.87, boundingBox: CGRect(x: 0.6, y: 0.5, width: 0.25, height: 0.2))
            ],
            viewSize: CGSize(width: 400, height: 600)
        )
    }
}
