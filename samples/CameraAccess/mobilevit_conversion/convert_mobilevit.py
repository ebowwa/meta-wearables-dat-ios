"""
Convert apple/deeplabv3-mobilevit-small to CoreML

This script downloads the MobileViT + DeepLabV3 semantic segmentation model
from HuggingFace and converts it to CoreML format for iOS deployment.

The model outputs logits for 21 PASCAL VOC classes:
  0: background, 1: aeroplane, 2: bicycle, 3: bird, 4: boat, 5: bottle,
  6: bus, 7: car, 8: cat, 9: chair, 10: cow, 11: dining table, 12: dog,
  13: horse, 14: motorbike, 15: person, 16: potted plant, 17: sheep,
  18: sofa, 19: train, 20: tv/monitor

Usage:
  uv run python convert_mobilevit.py
"""

import torch
import coremltools as ct
from transformers import MobileViTForSemanticSegmentation, MobileViTImageProcessor


# PASCAL VOC class labels
PASCAL_VOC_CLASSES = [
    "background", "aeroplane", "bicycle", "bird", "boat", "bottle",
    "bus", "car", "cat", "chair", "cow", "dining table", "dog",
    "horse", "motorbike", "person", "potted plant", "sheep",
    "sofa", "train", "tv/monitor"
]


class SegmentationWrapper(torch.nn.Module):
    """Wrapper to extract logits tensor from model output dictionary."""
    
    def __init__(self, model):
        super().__init__()
        self.model = model
    
    def forward(self, x):
        # MobileViT returns SemanticSegmenterOutput with .logits attribute
        outputs = self.model(x)
        return outputs.logits


def convert_mobilevit_to_coreml():
    print("📦 Loading MobileViT + DeepLabV3 from HuggingFace...")
    model = MobileViTForSemanticSegmentation.from_pretrained("apple/deeplabv3-mobilevit-small")
    model.eval()
    
    # Wrap model to extract logits
    wrapped_model = SegmentationWrapper(model)
    
    # Create dummy input (1, 3, 512, 512) - model's native resolution
    print("🔧 Tracing model with 512x512 input...")
    dummy_input = torch.randn(1, 3, 512, 512)
    
    # Trace the model
    with torch.no_grad():
        traced_model = torch.jit.trace(wrapped_model, dummy_input)
    
    print("🔄 Converting to CoreML...")
    
    # Convert to CoreML
    mlmodel = ct.convert(
        traced_model,
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 3, 512, 512),
                scale=1/255.0,
                bias=[0, 0, 0],
                color_layout=ct.colorlayout.RGB
            )
        ],
        outputs=[
            ct.TensorType(name="segmentation_logits")
        ],
        minimum_deployment_target=ct.target.iOS16,
        convert_to="mlprogram"
    )
    
    # Add metadata
    mlmodel.author = "Apple (via HuggingFace)"
    mlmodel.license = "Apple Sample Code License"
    mlmodel.short_description = "MobileViT + DeepLabV3 semantic segmentation (PASCAL VOC 21 classes)"
    mlmodel.version = "1.0"
    
    # Add class labels as user-defined metadata
    mlmodel.user_defined_metadata["classes"] = ",".join(PASCAL_VOC_CLASSES)
    
    # Save the model
    output_path = "DeepLabV3MobileViT.mlpackage"
    mlmodel.save(output_path)
    print(f"✅ Saved {output_path}")
    
    # Print model info
    print("\n📊 Model Info:")
    print(f"  Input: image (1, 3, 512, 512)")
    print(f"  Output: segmentation_logits (1, 21, H, W)")
    print(f"  Classes: {len(PASCAL_VOC_CLASSES)}")
    print(f"  Target: iOS 16+")
    
    return output_path


if __name__ == "__main__":
    convert_mobilevit_to_coreml()
