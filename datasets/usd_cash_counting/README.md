# USD Cash Counting Dataset

A comprehensive dataset for detecting, classifying, and counting US currency (bills and coins).

## 📁 Directory Structure

```
usd_cash_counting/
├── images/
│   ├── train/          # Training images (80%)
│   ├── val/            # Validation images (10%)
│   └── test/           # Test images (10%)
├── labels/
│   ├── train/          # YOLO format labels for training
│   ├── val/            # YOLO format labels for validation
│   └── test/           # YOLO format labels for test
├── scripts/
│   ├── download_roboflow.py    # Download datasets from Roboflow
│   ├── merge_datasets.py       # Merge multiple datasets
│   └── add_images.py           # Add new images to dataset
├── data.yaml           # YOLO training configuration
├── classes.txt         # Class names file
└── README.md           # This file
```

## 🏷️ Classes (10 total)

| ID | Class | Value |
|----|-------|-------|
| 0 | penny | $0.01 |
| 1 | nickel | $0.05 |
| 2 | dime | $0.10 |
| 3 | quarter | $0.25 |
| 4 | dollar_bill | $1.00 |
| 5 | five_dollars | $5.00 |
| 6 | ten_dollars | $10.00 |
| 7 | twenty_dollars | $20.00 |
| 8 | fifty_dollars | $50.00 |
| 9 | hundred_dollars | $100.00 |

## 📊 Dataset Sources

- **USD Money (Roboflow)**: 5,600 bill images
- **Coin Counter Practice**: 8,450 coin images
- **Custom additions**: Your own images

## 🚀 Usage

### Download base datasets
```bash
python scripts/download_roboflow.py
```

### Add new images
```bash
python scripts/add_images.py --image path/to/image.jpg --split train
```

### Train with YOLOv8
```bash
yolo detect train data=data.yaml model=yolov8n.pt epochs=100
```

## ✏️ Adding Your Own Data

1. Take photos of bills/coins
2. Use Roboflow or LabelImg to annotate
3. Export in YOLO format
4. Run merge script to add to dataset

## 📝 Label Format (YOLO)

Each `.txt` label file contains one line per object:
```
<class_id> <x_center> <y_center> <width> <height>
```
All values are normalized (0-1) relative to image dimensions.
