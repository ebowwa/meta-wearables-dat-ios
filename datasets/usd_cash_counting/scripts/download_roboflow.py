#!/usr/bin/env python3
"""
Download USD currency datasets from Roboflow Universe.

Usage:
    python download_roboflow.py --api-key YOUR_API_KEY

Requires: pip install roboflow
"""

import os
import argparse
from pathlib import Path

# Dataset configurations
DATASETS = {
    "usd_bills": {
        "workspace": "objectdetection-nhb0l",
        "project": "usd-money",
        "version": 2,
        "description": "USD Bills dataset (5,600 images) - $1, $5, $10, $20, $50, $100",
        "format": "yolov8"
    },
    "dollar_bills_v20": {
        "workspace": "alex-hyams-cosqx",
        "project": "dollar-bill-detection",
        "version": 20,
        "description": "Dollar Bill Detection v20 (YOLOv8)",
        "format": "yolov8"
    },
    "front_back_usd_obb": {
        "workspace": "sg-knxss",
        "project": "front-back-of-usd",
        "version": 1,
        "description": "Front/Back USD OBB v1 (YOLOv8-OBB)",
        "format": "yolov8-obb"
    },
    "coin_counter": {
        "workspace": "adrian-fvgo3", 
        "project": "coin-counter-practice-5xh0x",
        "version": 1,
        "description": "Coin Counter Practice (8,450 images) - penny, nickel, dime, quarter + distractors"
    },
    "us_currency_coins": {
        "workspace": "most-current-coin-counter-6292022",
        "project": "us-currency-coins-o2oet",
        "version": 1,
        "description": "US Currency Coins (272 images) - multiple coins per image"
    }
}

# Class mapping from source datasets to our unified classes
CLASS_MAPPING = {
    # Coin mappings (various naming conventions in source datasets)
    "penny": 0, "Penny": 0, "1cent": 0, "1_cent": 0, "one_cent": 0,
    "nickel": 1, "Nickel": 1, "5cent": 1, "5_cent": 1, "five_cent": 1,
    "dime": 2, "Dime": 2, "10cent": 2, "10_cent": 2, "ten_cent": 2,
    "quarter": 3, "Quarter": 3, "25cent": 3, "25_cent": 3, "twenty_five_cent": 3,
    
    # Bill mappings
    "1": 4, "$1": 4, "one": 4, "1_dollar": 4, "dollar_bill": 4, "one_dollar": 4,
    "5": 5, "$5": 5, "five": 5, "5_dollar": 5, "five_dollars": 5, "five_dollar": 5,
    "10": 6, "$10": 6, "ten": 6, "10_dollar": 6, "ten_dollars": 6, "ten_dollar": 6,
    "20": 7, "$20": 7, "twenty": 7, "20_dollar": 7, "twenty_dollars": 7, "twenty_dollar": 7,
    "50": 8, "$50": 8, "fifty": 8, "50_dollar": 8, "fifty_dollars": 8, "fifty_dollar": 8,
    "100": 9, "$100": 9, "hundred": 9, "100_dollar": 9, "hundred_dollars": 9, "hundred_dollar": 9,
}

# Classes to skip (distractors from coin counter dataset)
SKIP_CLASSES = {"nut", "screw", "nail", "washer", "bolt"}


def download_dataset(api_key: str, dataset_name: str, output_dir: Path):
    """Download a single dataset from Roboflow."""
    from roboflow import Roboflow
    
    config = DATASETS[dataset_name]
    print(f"\n📥 Downloading: {config['description']}")
    
    rf = Roboflow(api_key=api_key)
    project = rf.workspace(config["workspace"]).project(config["project"])
    dataset = project.version(config["version"]).download(
        config.get("format", "yolov8"),
        location=str(output_dir / dataset_name)
    )
    
    print(f"✅ Downloaded to: {output_dir / dataset_name}")
    return dataset


def main():
    parser = argparse.ArgumentParser(description="Download USD currency datasets from Roboflow")
    parser.add_argument("--api-key", required=True, help="Roboflow API key")
    parser.add_argument("--datasets", nargs="+", choices=list(DATASETS.keys()) + ["all"],
                       default=["all"], help="Which datasets to download")
    parser.add_argument("--output", type=Path, default=Path("../raw_downloads"),
                       help="Output directory for raw downloads")
    args = parser.parse_args()
    
    output_dir = args.output.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    
    datasets_to_download = list(DATASETS.keys()) if "all" in args.datasets else args.datasets
    
    print("🏦 USD Cash Counting Dataset Downloader")
    print("=" * 50)
    print(f"Output directory: {output_dir}")
    print(f"Datasets to download: {datasets_to_download}")
    
    for dataset_name in datasets_to_download:
        try:
            download_dataset(args.api_key, dataset_name, output_dir)
        except Exception as e:
            print(f"❌ Failed to download {dataset_name}: {e}")
    
    print("\n✅ Downloads complete!")
    print(f"Next: Run 'python merge_datasets.py' to combine into unified format")


if __name__ == "__main__":
    main()
