# CoreML Model Conversion & Distribution Guide

This guide explains how to convert machines learning models (YOLO, PyTorch, ONNX) to CoreML, compile them for optimization, and host them for remote download in the app.

## 1. Prerequisites

You need a Mac with Xcode installed and a Python environment. We strongly recommend using **uv** for fast and reliable dependency management.

```bash
# Install uv (if not already installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Create and activate a virtual environment
uv venv
source .venv/bin/activate

# Install coremltools and ultralytics using uv
uv pip install coremltools ultralytics
```

## 2. Convert Model to CoreML

Use Python to convert your model to the `.mlpackage` format.

**Example: Converting YOLOv8 from PyTorch**

```python
from ultralytics import YOLO

# Load model
model = YOLO('yolov8n.pt')

# Export to CoreML
# nms=True adds Non-Maximum Suppression logic directly into the CoreML model
model.export(format='coreml', nms=True)

# Result: 'yolov8n.mlpackage'
```

## 3. Compile Model (Optional but Recommended)

While the app can compile `.mlpackage` files on-device, it is more efficient to pre-compile them, especially for large models. This reduces on-device processing time and storage usage.

```bash
# Clean previous output
rm -rf compiled_output/

# Compile the model
# xcrun coremlcompiler compile [SourceModel] [DestinationFolder]
xcrun coremlcompiler compile yolov8n.mlpackage ./compiled_output/

# Result: ./compiled_output/yolov8n.mlmodelc (This is a folder, not a file)
```

## 4. Package for Distribution

Since `.mlmodelc` is a directory, you must ZIP it for distribution.

### For App Auto-Handling (Future Feature)
If the app supports ZIP downloads, you would zip the compiled folder:
```bash
zip -r yolov8n.mlmodelc.zip yolov8n.mlmodelc
```

### For Current App Version (Single File Download)
Currently, the app supports downloading:
1.  **Raw `.mlmodel`** (Old format, single file) - *Slow, requires on-device compilation.*
2.  **`.mlpackage` (Archives)** - *Requires on-device compilation.* (Note: These are technically directories but often treated as bundles. Direct download servers must handle them as single files, which standard web servers do NOT. GitHub "Raw" view relies on single files).

**Best Practice for Now:**
Store the **Uncompiled `.mlmodel`** or **`.mlpackage`** on a server/GitHub.
The app currently has logic to download these and compile them locally.

**Hosting on GitHub:**
1.  Commit your `.mlpackage` or `.mlmodel` to a repo.
2.  Navigate to the file on GitHub.
3.  Copy the URL (e.g., `https://github.com/user/repo/blob/main/yolov8n.mlpackage`).
4.  Paste this URL into the app. The app assumes `github.com` links need conversion to "raw" format.

## 5. Hosting & Retrieval

### Hosting Options
-   **GitHub Repository**: Free, easy versioning. Use valid "Raw" URLs.
-   **S3 / Cloud Storage**: scalable, direct links.

### In-App Retrieval
1.  Open the Camera Access app.
2.  Go to the **Model Picker** (Long-press the Brain icon).
3.  Tap **+ (Add)**.
4.  Paste the URL.
5.  Tap **Add**. The app will download -> Compile -> Cache the model.

## Troubleshooting

-   **"Not a valid .mlmodelc file"**: The app mistakenly tried to use a raw file as a compiled bundle. Update the app to the latest version which includes the "Robust Compilation" fix.
-   **Download Fails**: Ensure the URL points directly to the file content, not an HTML page.
