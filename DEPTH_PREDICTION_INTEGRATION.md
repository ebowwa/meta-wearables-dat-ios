# Depth Prediction Integration

## Overview
Integrated **Depth Anything V2** (Apple's official replacement for FCRN) for monocular depth estimation in the CameraAccess app. Displays side-by-side video feed and depth map visualization.

## Why Depth Anything V2?

| Feature | FCRN (old) | Depth Anything V2 (new) |
|---------|-------------|-------------------------|
| Model Size | 127-254 MB | **50 MB** (F16) |
| Inference (iPhone 12 Pro) | ~134 ms | **~31 ms** (4x faster!) |
| Input Resolution | 304×228 | **518×392** (higher quality) |
| Format | .mlmodel | .mlpackage |
| Training | Synthetic data | **600K synthetic + 62M real images** |
| Accuracy | Older baseline | **State-of-the-art** |

## Files Created/Modified

### New Files
- `samples/CameraAccess/CameraAccess/ViewModels/DepthPredictionService.swift`
  - Depth Anything V2 integration
  - Uses CoreML for inference
  - Includes heatmap colormap visualization
  - CIImage-based pipeline for better performance

### Modified Files
- `samples/CameraAccess/CameraAccess/ViewModels/StreamSessionViewModel.swift`
  - Added depth prediction service integration
  - Added toggle functionality for depth prediction
  - Added Combine subscriptions for depth map updates

- `samples/CameraAccess/CameraAccess/Views/StreamView.swift`
  - Added side-by-side display (video + depth map)
  - Added depth prediction toggle button (cube icon)
  - Shows loading state during inference

## Setup Instructions

### 1. Download Depth Anything V2 Model

**Option A: Using huggingface-cli (Recommended)**
```bash
# Install huggingface-cli if needed
brew install huggingface-cli

# Download the F16 variant (50MB, faster inference)
huggingface-cli download \
  --local-dir models --local-dir-use-symlinks False \
  apple/coreml-depth-anything-v2-small \
  --include "DepthAnythingV2SmallF16.mlpackage/*"
```

**Option B: Direct Download**
- Visit: https://huggingface.co/apple/coreml-depth-anything-v2-small
- Download `DepthAnythingV2SmallF16.mlpackage`

**Sources:**
- [HuggingFace Model](https://huggingface.co/apple/coreml-depth-anything-v2-small)
- [Apple Core ML Models](https://developer.apple.com/machine-learning/models/)
- [GitHub Examples](https://github.com/huggingface/coreml-examples/tree/main/depth-anything-example)

### 2. Add Model to Xcode Project

1. Open `samples/CameraAccess/CameraAccess.xcodeproj` in Xcode
2. Drag `DepthAnythingV2SmallF16.mlpackage` into the project navigator
3. Make sure "Copy items if needed" is unchecked
4. Ensure CameraAccess target is checked

### 3. Enable Model in Code

In `DepthPredictionService.swift`, uncomment lines 188-193 in `ModelWrapper.init()`:

```swift
init() {
    do {
        model = try DepthAnythingV2SmallF16()
        print("[DepthPrediction] Depth Anything V2 model loaded")
    } catch {
        print("[DepthPrediction] Model not available: \(error)")
    }
}
```

And uncomment lines 198-202 in `ModelWrapper.prediction()`:

```swift
func prediction(image: CVPixelBuffer) throws -> ModelOutput {
    guard let depthModel = model as? DepthAnythingV2SmallF16 else {
        throw ModelError.notLoaded
    }
    let result = try depthModel.prediction(image: image)
    return ModelOutput(depth: result.depth)
}
```

### 4. Build and Run

```bash
cd samples/CameraAccess
xcodebuild -project CameraAccess.xcodeproj -scheme CameraAccess build
```

Or open in Xcode and run (⌘R).

## Usage

1. Start streaming from your Meta wearable device
2. Tap the **cube icon** button in the bottom controls to toggle depth prediction
3. The view will split to show:
   - **Left**: Original video feed from glasses
   - **Right**: Real-time depth map
4. Tap the cube icon again to disable depth prediction

## Technical Details

### Model Specifications
- **Architecture**: DPT with DINOv2 backbone
- **Parameters**: 24.8M
- **Input**: 518×392 RGB image
- **Output**: 518×392 depth map (relative depth)
- **Precision**: Float16 (recommended) or Float32
- **Compute**: Apple Neural Engine

### Performance Benchmarks

| Device | OS | Inference Time |
|--------|-----|----------------|
| iPhone 12 Pro Max | 18.0 | 31.10 ms |
| iPhone 15 Pro Max | 17.4 | 33.90 ms |
| MacBook Pro M1 Max | 15.0 | 32.80 ms |
| MacBook Pro M3 Max | 15.0 | 24.58 ms |

### Implementation Notes
- Uses reusable CVPixelBuffer for efficiency
- Asynchronous inference on dedicated queue
- CIImage-based pipeline for optimal performance
- Proper memory management with weak references
- Heatmap colormap visualization option

## References

- [Depth Anything V2 Paper](https://arxiv.org/abs/2406.09414)
- [HuggingFace CoreML Examples](https://github.com/huggingface/coreml-examples)
- [Apple Core ML Documentation](https://developer.apple.com/documentation/coreml)
