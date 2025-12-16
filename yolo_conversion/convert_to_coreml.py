"""
Convert Race Classification YOLOv8n model to CoreML format for iOS deployment.

This script downloads the model from HuggingFace and exports to CoreML with INT8 quantization.
"""

from huggingface_hub import hf_hub_download
from ultralytics import YOLO
import os

# Download the nano model (3MB, fastest for mobile)
print("📥 Downloading Race-CLS-FairFace_yolov8n.pt from HuggingFace...")
model_path = hf_hub_download(
    repo_id="Anzhc/Race-Classification-FairFace-YOLOv8",
    filename="Race-CLS-FairFace_yolov8n.pt"
)
print(f"✅ Downloaded to: {model_path}")

# Load the model
print("🔧 Loading YOLO model...")
model = YOLO(model_path)

# Export to CoreML (nano model is already small, skip INT8 quantization)
print("📦 Exporting to CoreML...")
model.export(format="coreml", nms=False)

print("✅ Export complete! Look for .mlpackage file in the model directory.")
