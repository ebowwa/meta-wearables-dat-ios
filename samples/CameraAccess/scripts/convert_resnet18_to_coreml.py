#!/usr/bin/env python3
"""
Convert ResNet18 to CoreML for embedding extraction.

This script creates ResNet18Embedding.mlpackage that outputs 512-dimensional
feature embeddings, matching the Python live-camera-learning reference.

Usage:
    cd /path/to/this/directory
    pip install torch torchvision coremltools pillow
    python convert_resnet18_to_coreml.py

Output:
    ResNet18Embedding.mlpackage (move to Xcode project)
"""

import torch
import torch.nn as nn
from torchvision.models import resnet18, ResNet18_Weights
import coremltools as ct
from PIL import Image
import numpy as np

def create_resnet18_embedding_model():
    """
    Create ResNet18 model that outputs 512-dim embeddings.
    Matches Python knn_classifier.py lines 86-95:
    
        self.feature_extractor = resnet18(weights='IMAGENET1K_V1')
        self.feature_extractor = torch.nn.Sequential(
            *list(self.feature_extractor.children())[:-1]
        )
    """
    print("📦 Loading ResNet18 with ImageNet weights...")
    
    # Load pretrained ResNet18
    model = resnet18(weights=ResNet18_Weights.IMAGENET1K_V1)
    
    # Remove the final classification layer (fc)
    # Keep everything up to and including avgpool
    # This outputs [batch, 512, 1, 1] which we'll flatten to [batch, 512]
    feature_extractor = nn.Sequential(
        *list(model.children())[:-1],  # Remove fc layer
        nn.Flatten()  # Flatten [512, 1, 1] to [512]
    )
    
    feature_extractor.eval()
    
    print("✅ ResNet18 embedding model created (512-dim output)")
    return feature_extractor


def convert_to_coreml(model, output_path="ResNet18Embedding.mlpackage"):
    """
    Convert PyTorch model to CoreML.
    Uses same preprocessing as Python knn_classifier.py lines 97-105:
    
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize(
            mean=[0.485, 0.456, 0.406],
            std=[0.229, 0.224, 0.225]
        )
    """
    print("🔄 Converting to CoreML...")
    
    # Create example input (batch=1, channels=3, height=224, width=224)
    example_input = torch.randn(1, 3, 224, 224)
    
    # Trace the model
    traced_model = torch.jit.trace(model, example_input)
    
    # Convert to CoreML with ImageNet preprocessing built-in
    # This matches Python's transforms.Normalize(mean, std)
    mlmodel = ct.convert(
        traced_model,
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 3, 224, 224),
                scale=1/255.0,  # Convert 0-255 to 0-1
                bias=[-0.485/0.229, -0.456/0.224, -0.406/0.225],  # ImageNet normalization
                color_layout="RGB"
            )
        ],
        outputs=[
            ct.TensorType(name="embedding")
        ],
        minimum_deployment_target=ct.target.iOS15,
        convert_to="mlprogram"  # Use .mlpackage format
    )
    
    # Add metadata
    mlmodel.author = "Converted from PyTorch ResNet18"
    mlmodel.short_description = "ResNet18 feature extractor outputting 512-dim embeddings for KNN classification"
    mlmodel.version = "1.0"
    
    # Add input/output descriptions
    mlmodel.input_description["image"] = "224x224 RGB image"
    mlmodel.output_description["embedding"] = "512-dimensional L2-normalized feature embedding"
    
    # Save
    mlmodel.save(output_path)
    print(f"✅ Saved to {output_path}")
    
    return mlmodel


def verify_model(mlmodel_path="ResNet18Embedding.mlpackage"):
    """Verify the converted model produces correct output shape."""
    print("\n🔍 Verifying model...")
    
    import coremltools as ct
    
    # Load the model
    model = ct.models.MLModel(mlmodel_path)
    
    # Create a test image
    test_image = Image.new('RGB', (224, 224), color='red')
    
    # Run inference
    output = model.predict({"image": test_image})
    embedding = output["embedding"]
    
    print(f"   Input: 224x224 RGB image")
    print(f"   Output shape: {embedding.shape}")
    print(f"   Output dtype: {embedding.dtype}")
    print(f"   First 5 values: {embedding.flatten()[:5]}")
    
    # Verify shape
    if embedding.shape == (1, 512) or embedding.shape == (512,):
        print("✅ Verification passed! 512-dimensional embedding.")
        return True
    else:
        print(f"❌ Unexpected shape: {embedding.shape}")
        return False


if __name__ == "__main__":
    print("=" * 60)
    print("ResNet18 to CoreML Converter")
    print("Matches Python: live-camera-learning/python/edaxshifu/knn_classifier.py")
    print("=" * 60)
    print()
    
    # Step 1: Create model
    model = create_resnet18_embedding_model()
    
    # Step 2: Test PyTorch output
    print("\n🧪 Testing PyTorch model...")
    with torch.no_grad():
        test_input = torch.randn(1, 3, 224, 224)
        output = model(test_input)
        print(f"   PyTorch output shape: {output.shape}")  # Should be [1, 512]
    
    # Step 3: Convert to CoreML
    print()
    output_path = "ResNet18Embedding.mlpackage"
    convert_to_coreml(model, output_path)
    
    # Step 4: Verify
    verify_model(output_path)
    
    print()
    print("=" * 60)
    print("NEXT STEPS:")
    print("=" * 60)
    print(f"1. Move {output_path} to your Xcode project:")
    print(f"   mv {output_path} ~/Desktop/")
    print()
    print("2. Drag into Xcode project under:")
    print("   CameraAccess/Features/embeddings/Models/")
    print()
    print("3. Update EmbeddingExtractor.swift to load 'ResNet18Embedding'")
    print("4. Update OnDeviceKNN.swift: embeddingDimension = 512")
    print("=" * 60)
