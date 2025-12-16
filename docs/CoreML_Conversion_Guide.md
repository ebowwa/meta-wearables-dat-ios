# CoreML Model Conversion & Distribution Guide

This guide explains how to convert machine learning models (YOLO, PyTorch, ONNX) to CoreML, compile them for optimization, and host them for remote download in the app.

> [!TIP]
> This repository has working examples on different branches. See [Branch-Specific Examples](#branch-specific-examples) for real implementations.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Convert Model to CoreML](#2-convert-model-to-coreml)
3. [Quantization Options](#3-quantization-options)
4. [Compile Model](#4-compile-model-optional-but-recommended)
5. [Package for Distribution](#5-package-for-distribution)
6. [Hosting & Retrieval](#6-hosting--retrieval)
7. [Swift Integration](#7-swift-integration)
8. [Branch-Specific Examples](#branch-specific-examples)
9. [Troubleshooting](#troubleshooting)

---

## 1. Prerequisites

You need a Mac with Xcode installed and a Python environment. We strongly recommend using **uv** for fast and reliable dependency management.

```bash
# Install uv (if not already installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Create and activate a virtual environment
uv venv
source .venv/bin/activate

# Install core dependencies
uv pip install coremltools ultralytics

# Optional: For HuggingFace model downloads
uv pip install huggingface_hub
```

### Project Structure

```
yolo_conversion/
├── .python-version      # Python version (e.g., 3.11)
├── pyproject.toml       # Project metadata
├── convert_to_coreml.py # Conversion script
└── .venv/               # Virtual environment (git-ignored)
```

---

## 2. Convert Model to CoreML

### Standard YOLO Models (Ultralytics)

Use the `ultralytics` library to export YOLO models directly:

```python
from ultralytics import YOLO

# Load a pretrained model (downloads automatically if not present)
model = YOLO('yolov8n.pt')  # nano variant for mobile

# Export to CoreML
# nms=True embeds Non-Maximum Suppression into the model
model.export(format='coreml', nms=True)

# Output: 'yolov8n.mlpackage'
```

### From HuggingFace

Download models from HuggingFace Hub before conversion:

```python
from huggingface_hub import hf_hub_download
from ultralytics import YOLO

# Download model weights
model_path = hf_hub_download(
    repo_id="Anzhc/Race-Classification-FairFace-YOLOv8",
    filename="Race-CLS-FairFace_yolov8n.pt"
)

# Load and export
model = YOLO(model_path)
model.export(format="coreml", nms=False)  # nms=False for classification

# Output: 'Race-CLS-FairFace_yolov8n.mlpackage'
```

### From Custom Weights

```python
from ultralytics import YOLO

# Load your custom-trained model
model = YOLO('path/to/best.pt')

# Export with custom settings
model.export(
    format='coreml',
    nms=True,
    imgsz=640,  # Input image size
)
```

### From PyTorch (Non-YOLO)

For generic PyTorch models, use `coremltools` directly:

```python
import torch
import coremltools as ct

# Load PyTorch model
model = torch.load('model.pt')
model.eval()

# Trace the model
example_input = torch.rand(1, 3, 224, 224)
traced_model = torch.jit.trace(model, example_input)

# Convert to CoreML
mlmodel = ct.convert(
    traced_model,
    inputs=[ct.ImageType(name="image", shape=example_input.shape)],
    minimum_deployment_target=ct.target.iOS15
)

mlmodel.save("model.mlpackage")
```

---

## 3. Quantization Options

Quantization reduces model size and improves inference speed at the cost of some accuracy.

| Type | Size Reduction | Use Case |
|------|---------------|----------|
| Float32 | Baseline | Maximum accuracy |
| Float16 | ~50% | Good balance (default for iOS) |
| INT8 | ~75% | Fastest, some accuracy loss |
| INT8 LUT | ~75% | Fastest with lookup tables |

### Apply Quantization

```python
import coremltools as ct
from coremltools.models.neural_network import quantization_utils

# Load existing model
model = ct.models.MLModel("model.mlpackage")

# Quantize to 8-bit
quantized_model = quantization_utils.quantize_weights(model, nbits=8)
quantized_model.save("model_int8.mlpackage")
```

### Using Ultralytics Export

```python
from ultralytics import YOLO

model = YOLO('yolov8n.pt')

# INT8 quantization during export
model.export(format='coreml', int8=True)
```

> [!NOTE]
> Apple's pre-built models (like `YOLOv3Int8LUT.mlmodel`) use INT8 with Look-Up Tables for optimal mobile performance without conversion.

---

## 4. Compile Model (Optional but Recommended)

Pre-compiling reduces on-device processing time significantly.

```bash
# Clean previous output
rm -rf compiled_output/

# Compile the model
xcrun coremlcompiler compile yolov8n.mlpackage ./compiled_output/

# Result: ./compiled_output/yolov8n.mlmodelc (folder, not a file)
```

### Verify Compilation

```bash
# Check the compiled bundle contents
ls -la compiled_output/yolov8n.mlmodelc/
# Should contain: model.mil, coremldata.bin, etc.
```

---

## 5. Package for Distribution

### File Formats

| Format | Extension | Size | On-Device Compile | Best For |
|--------|-----------|------|-------------------|----------|
| Source | `.mlmodel` | Large | Required | Legacy models |
| Package | `.mlpackage` | Medium | Required | Modern workflow |
| Compiled | `.mlmodelc` | Optimized | No | Production |

### ZIP for Distribution

Since `.mlmodelc` is a directory:

```bash
# Package compiled model
cd compiled_output/
zip -r yolov8n.mlmodelc.zip yolov8n.mlmodelc

# Result: yolov8n.mlmodelc.zip (single file for download)
```

### Current App Support

The app currently supports:
1. **Raw `.mlmodel`** — Slow, requires on-device compilation
2. **`.mlpackage`** — Modern format, requires on-device compilation

> [!IMPORTANT]
> GitHub "Raw" URLs work for single files. For `.mlpackage` bundles, commit the entire folder and use the repo URL.

---

## 6. Hosting & Retrieval

### Hosting Options

| Platform | Pros | Cons |
|----------|------|------|
| GitHub | Free, versioned | Large files need LFS |
| S3/GCS | Scalable, fast | Costs money |
| HuggingFace | ML-focused, free | May have rate limits |

### GitHub Hosting

1. Commit your `.mlpackage` or `.mlmodel` to a repo
2. Navigate to the file on GitHub
3. Copy the URL: `https://github.com/user/repo/blob/main/model.mlpackage`
4. The app converts this to a raw download URL automatically

### In-App Retrieval

1. Open the Camera Access app
2. Long-press the **Brain icon** → Model Picker
3. Tap **+ (Add)**
4. Paste the model URL
5. Tap **Add** → Downloads → Compiles → Caches

---

## 7. Swift Integration

### Basic Loading

```swift
import CoreML
import Vision

class DetectionService {
    private var model: VNCoreMLModel?
    
    func loadModel() throws {
        // From bundle
        guard let modelURL = Bundle.main.url(
            forResource: "YOLOv8n", 
            withExtension: "mlmodelc"
        ) else {
            throw ModelError.notFound
        }
        
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine  // Use ANE when available
        
        let mlModel = try MLModel(contentsOf: modelURL, configuration: config)
        self.model = try VNCoreMLModel(for: mlModel)
    }
}
```

### Async Loading (iOS 16+)

```swift
func loadModel() async throws {
    guard let modelURL = Bundle.main.url(
        forResource: "YOLOv8n", 
        withExtension: "mlmodelc"
    ) ?? Bundle.main.url(
        forResource: "YOLOv8n", 
        withExtension: "mlpackage"
    ) else {
        throw ModelError.notFound
    }
    
    let config = MLModelConfiguration()
    config.computeUnits = .cpuAndNeuralEngine
    
    let mlModel = try await MLModel.load(contentsOf: modelURL, configuration: config)
    self.model = try VNCoreMLModel(for: mlModel)
}
```

### Running Inference

```swift
func detect(in image: UIImage) async -> [Detection] {
    guard let model = model, let cgImage = image.cgImage else { return [] }
    
    return await withCheckedContinuation { continuation in
        let request = VNCoreMLRequest(model: model) { request, error in
            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                continuation.resume(returning: [])
                return
            }
            
            let detections = results.compactMap { obs -> Detection? in
                guard let label = obs.labels.first else { return nil }
                return Detection(
                    label: label.identifier,
                    confidence: label.confidence,
                    boundingBox: obs.boundingBox
                )
            }
            continuation.resume(returning: detections)
        }
        
        request.imageCropAndScaleOption = .scaleFill
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
}
```

---

## Branch-Specific Examples

This repository contains working implementations on different branches:

### `feature/yolov3-realtime-detection`

**Model**: Apple's pre-built `YOLOv3Int8LUT.mlmodel` (62 MB)

- **Source**: Apple ML Gallery (no conversion needed)
- **Quantization**: INT8 with Look-Up Tables
- **Classes**: 80 COCO object categories
- **Use Case**: General object detection

```swift
// ObjectDetectionService.swift
guard let modelURL = Bundle.main.url(
    forResource: "YOLOv3Int8LUT", 
    withExtension: "mlmodelc"
) else { return }
```

---

### `feature/yolov8-race-classification`

**Model**: `Race-CLS-FairFace_yolov8n.mlpackage` (~3 MB)

- **Source**: [HuggingFace](https://huggingface.co/Anzhc/Race-Classification-FairFace-YOLOv8)
- **Quantization**: None (nano variant already small)
- **Classes**: 7 ethnicity categories (FairFace dataset)
- **Use Case**: Face ethnicity classification

**Conversion Script**:
```python
from huggingface_hub import hf_hub_download
from ultralytics import YOLO

model_path = hf_hub_download(
    repo_id="Anzhc/Race-Classification-FairFace-YOLOv8",
    filename="Race-CLS-FairFace_yolov8n.pt"
)

model = YOLO(model_path)
model.export(format="coreml", nms=False)  # Classification, no NMS
```

---

### `feature/yolo11-poker-detection`

**Model**: `YOLO11PokerInt8LUT.mlpackage`

- **Source**: Custom-trained on poker dataset
- **Quantization**: INT8 LUT
- **Classes**: 52 cards + hand rankings
- **Use Case**: Poker card detection and hand analysis

**Conversion Script**:
```python
from ultralytics import YOLO

model = YOLO('path/to/poker_best.pt')
model.export(format='coreml', nms=True, int8=True)
```

---

## Troubleshooting

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `"Not a valid .mlmodelc file"` | Raw file used as compiled bundle | Update app or use correct file type |
| `Download Fails` | URL points to HTML page | Use raw/direct download URL |
| `Model not found in bundle` | Wrong extension or missing from target | Verify file is in Xcode target membership |
| `Neural Engine not available` | Running on simulator | Test on physical device |

### Debugging Model Loading

```swift
// List all bundle resources
if let resourcePath = Bundle.main.resourcePath {
    let files = try? FileManager.default.contentsOfDirectory(atPath: resourcePath)
    print("Bundle contents:", files ?? [])
}
```

### Verify Model Outputs

```swift
// Print model description
if let model = try? MLModel(contentsOf: modelURL) {
    print("Inputs:", model.modelDescription.inputDescriptionsByName)
    print("Outputs:", model.modelDescription.outputDescriptionsByName)
}
```
