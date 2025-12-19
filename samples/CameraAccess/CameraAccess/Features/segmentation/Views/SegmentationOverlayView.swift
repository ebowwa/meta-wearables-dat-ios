/*
 * SegmentationOverlayView.swift
 * CameraAccess
 *
 * SwiftUI view for rendering semantic segmentation masks.
 */

import SwiftUI

struct SegmentationOverlayView: View {
    let result: SegmentationResult?
    var opacity: Double = 0.5
    
    var body: some View {
        GeometryReader { geometry in
            if let result = result, !result.mask.isEmpty {
                Canvas { context, size in
                    let mask = result.mask
                    let height = mask.count
                    let width = mask.first?.count ?? 0
                    guard width > 0, height > 0 else { return }
                    
                    let scaleX = size.width / CGFloat(width)
                    let scaleY = size.height / CGFloat(height)
                    
                    // Downsample for performance (render every Nth pixel)
                    let step = max(1, min(width, height) / 64)
                    
                    for y in stride(from: 0, to: height, by: step) {
                        for x in stride(from: 0, to: width, by: step) {
                            let classId = mask[y][x]
                            guard classId != 0,
                                  let segClass = SegmentationClass(rawValue: classId) else { continue }
                            
                            let rect = CGRect(
                                x: CGFloat(x) * scaleX,
                                y: CGFloat(y) * scaleY,
                                width: scaleX * CGFloat(step),
                                height: scaleY * CGFloat(step)
                            )
                            context.fill(Path(rect), with: .color(Color(segClass.color)))
                        }
                    }
                }
                .opacity(opacity)
            }
        }
    }
}

/// Compact stats view for segmentation
struct SegmentationStatsView: View {
    let result: SegmentationResult?
    
    var body: some View {
        if let result = result {
            VStack(alignment: .leading, spacing: 4) {
                Text("Segmentation")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                
                Text("\(String(format: "%.0f", result.processingTimeMs))ms")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
                
                ForEach(result.detectedClasses, id: \.rawValue) { segClass in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(segClass.color))
                            .frame(width: 8, height: 8)
                        Text(segClass.displayName)
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(8)
            .background(.ultraThinMaterial.opacity(0.8))
            .cornerRadius(8)
        }
    }
}

#Preview {
    ZStack {
        Color.black
        SegmentationStatsView(result: nil)
    }
}
