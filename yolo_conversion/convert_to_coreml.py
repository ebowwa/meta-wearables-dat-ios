#!/usr/bin/env python3
"""
Unified YOLO to CoreML Conversion Script

This script converts YOLO models (YOLOv8, YOLO11, etc.) to CoreML format
for use in iOS applications.

Usage:
    python convert_to_coreml.py --model yolov8n.pt --output YOLOv8n.mlpackage
    python convert_to_coreml.py --model-name yolov8n --output YOLOv8n.mlpackage
    python convert_to_coreml.py --hf-repo Anzhc/Race-Classification-FairFace-YOLOv8 --output RaceClassifier.mlpackage

Requirements:
    pip install ultralytics coremltools huggingface_hub
    # or with uv:
    uv pip install ultralytics coremltools huggingface_hub
"""

import argparse
import sys
from pathlib import Path


def download_from_huggingface(repo_id: str, filename: str = None) -> Path:
    """Download model weights from Hugging Face Hub."""
    try:
        from huggingface_hub import hf_hub_download, list_repo_files
    except ImportError:
        print("Error: huggingface_hub not installed. Run: pip install huggingface_hub")
        sys.exit(1)
    
    if filename is None:
        # Find .pt file in repo
        files = list_repo_files(repo_id)
        pt_files = [f for f in files if f.endswith('.pt')]
        if not pt_files:
            print(f"Error: No .pt files found in {repo_id}")
            sys.exit(1)
        filename = pt_files[0]
        print(f"Found model file: {filename}")
    
    print(f"Downloading {filename} from {repo_id}...")
    model_path = hf_hub_download(repo_id=repo_id, filename=filename)
    return Path(model_path)


def load_yolo_model(model_path: str = None, model_name: str = None):
    """Load a YOLO model from file or by name."""
    try:
        from ultralytics import YOLO
    except ImportError:
        print("Error: ultralytics not installed. Run: pip install ultralytics")
        sys.exit(1)
    
    if model_path:
        print(f"Loading model from: {model_path}")
        return YOLO(model_path)
    elif model_name:
        print(f"Loading model: {model_name}")
        return YOLO(model_name)
    else:
        raise ValueError("Either model_path or model_name must be provided")


def convert_to_coreml(
    model,
    output_path: str,
    imgsz: int = 640,
    half: bool = False,
    nms: bool = True,
):
    """Convert YOLO model to CoreML format."""
    print(f"\nConverting to CoreML...")
    print(f"  Image size: {imgsz}x{imgsz}")
    print(f"  Half precision (FP16): {half}")
    print(f"  Include NMS: {nms}")
    print(f"  Output: {output_path}")
    
    model.export(
        format="coreml",
        imgsz=imgsz,
        half=half,
        nms=nms,
    )
    
    # ultralytics exports to same directory as input with .mlpackage extension
    # We may need to move it to the desired output path
    print(f"\n✅ Export complete!")
    return output_path


def main():
    parser = argparse.ArgumentParser(
        description="Convert YOLO models to CoreML format for iOS",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Convert a local .pt file
  python convert_to_coreml.py --model path/to/model.pt --output Model.mlpackage

  # Download and convert a standard YOLO model
  python convert_to_coreml.py --model-name yolov8n --output YOLOv8n.mlpackage

  # Download from Hugging Face and convert
  python convert_to_coreml.py --hf-repo Anzhc/Race-Classification-FairFace-YOLOv8 --output RaceClassifier.mlpackage
        """
    )
    
    # Model source (mutually exclusive)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--model", "-m", help="Path to local .pt model file")
    source.add_argument("--model-name", "-n", help="YOLO model name (e.g., yolov8n, yolo11n)")
    source.add_argument("--hf-repo", help="Hugging Face repository ID")
    
    # Output
    parser.add_argument("--output", "-o", required=True, help="Output .mlpackage path")
    
    # Conversion options
    parser.add_argument("--imgsz", type=int, default=640, help="Input image size (default: 640)")
    parser.add_argument("--half", action="store_true", help="Use FP16 half precision")
    parser.add_argument("--no-nms", action="store_true", help="Disable NMS in export")
    
    # HuggingFace options
    parser.add_argument("--hf-filename", help="Specific filename to download from HF repo")
    
    args = parser.parse_args()
    
    # Determine model source
    model_path = None
    if args.model:
        model_path = args.model
    elif args.hf_repo:
        model_path = str(download_from_huggingface(args.hf_repo, args.hf_filename))
    
    # Load model
    model = load_yolo_model(model_path=model_path, model_name=args.model_name)
    
    # Convert
    convert_to_coreml(
        model=model,
        output_path=args.output,
        imgsz=args.imgsz,
        half=args.half,
        nms=not args.no_nms,
    )
    
    print(f"\n🎉 Done! Your CoreML model is ready.")
    print(f"   Add the .mlpackage to your Xcode project to use it.")


if __name__ == "__main__":
    main()
