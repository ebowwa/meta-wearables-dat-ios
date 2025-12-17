# YOLO Model Integration Guide for iOS

This guide explains how to integrate YOLO object detection models into the Meta DAT iOS app.

## Overview

The integration process has three main steps:
1. **Convert** the YOLO model to CoreML format
2. **Add** the `.mlpackage` to your Xcode project
3. **Implement** Swift code to run inference

> [!TIP]
> For the overall system design and composability patterns, see [YOLO Composable Architecture](./YOLO_COMPOSABLE_ARCHITECTURE.md).

---

## Step 1: Convert Model to CoreML

### Setup Environment

```bash
cd yolo_conversion

# Create virtual environment
uv venv
source .venv/bin/activate

# Install dependencies
uv pip install ultralytics coremltools huggingface_hub
```

### Run Conversion

```bash
# Standard YOLO model
python convert_to_coreml.py --model-name yolov8n --output YOLOv8n.mlpackage

# From Hugging Face
python convert_to_coreml.py --hf-repo Anzhc/Race-Classification-FairFace-YOLOv8 --output RaceClassifier.mlpackage

# Custom weights
python convert_to_coreml.py --model path/to/weights.pt --output Custom.mlpackage
```

---

## Step 2: Add to Xcode

1. Drag the `.mlpackage` into `samples/CameraAccess/CameraAccess/Models/`
2. Check "Copy items if needed"
3. Add to target `CameraAccess`
4. Build — Xcode generates the Swift interface automatically

---

## Step 3: Implement Swift Code

### Create Model Struct

```swift
// Models/YourDetection.swift
import Foundation

struct YourDetection: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
    let boundingBox: CGRect  // normalized 0-1
}
```

### Create Detection Service

```swift
// Services/YourDetectionService.swift
import Vision
import CoreML
import UIKit

class YourDetectionService {
    private var model: VNCoreMLModel?
    
    init() {
        do {
            let config = MLModelConfiguration()
            let mlModel = try YourModel(configuration: config).model
            model = try VNCoreMLModel(for: mlModel)
        } catch {
            print("Failed to load model: \(error)")
        }
    }
    
    func detect(in image: UIImage, completion: @escaping ([YourDetection]) -> Void) {
        guard let model = model,
              let cgImage = image.cgImage else {
            completion([])
            return
        }
        
        let request = VNCoreMLRequest(model: model) { request, error in
            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                completion([])
                return
            }
            
            let detections = results.map { observation in
                YourDetection(
                    label: observation.labels.first?.identifier ?? "Unknown",
                    confidence: observation.labels.first?.confidence ?? 0,
                    boundingBox: observation.boundingBox
                )
            }
            completion(detections)
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
}
```

### Integrate with ViewModel

Add service property and call detection when frames arrive:

```swift
// In StreamSessionViewModel.swift
private let detectionService = YourDetectionService()

func processFrame(_ image: UIImage) {
    detectionService.detect(in: image) { [weak self] detections in
        DispatchQueue.main.async {
            self?.currentDetections = detections
        }
    }
}
```

---

## Tips

- **Performance**: Use `yolov8n` or `yolo11n` (nano) variants for real-time on-device inference
- **Image Size**: Default 640x640; smaller sizes (320) run faster but less accurate
- **Threading**: Run inference on background queue, update UI on main queue
