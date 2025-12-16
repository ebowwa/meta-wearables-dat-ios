# YOLO Conversion Environment

This directory contains tools for converting YOLO models to CoreML format.

## Quick Start

```bash
# Create virtual environment with uv
uv venv
source .venv/bin/activate

# Install dependencies
uv pip install ultralytics coremltools huggingface_hub

# Convert a model
python convert_to_coreml.py --model-name yolov8n --output YOLOv8n.mlpackage
```

## Usage Examples

### Convert a standard YOLO model
```bash
python convert_to_coreml.py --model-name yolov8n --output YOLOv8n.mlpackage
python convert_to_coreml.py --model-name yolo11n --output YOLO11n.mlpackage
```

### Convert a local .pt file
```bash
python convert_to_coreml.py --model path/to/weights.pt --output Model.mlpackage
```

### Download from Hugging Face and convert
```bash
python convert_to_coreml.py --hf-repo Anzhc/Race-Classification-FairFace-YOLOv8 --output RaceClassifier.mlpackage
```

### Options
- `--imgsz`: Input image size (default: 640)
- `--half`: Use FP16 half precision
- `--no-nms`: Disable NMS in export

## Adding to Xcode

1. Drag the generated `.mlpackage` into your Xcode project
2. Ensure "Copy items if needed" is checked
3. Add to your app target
4. Xcode will auto-generate the Swift model class
