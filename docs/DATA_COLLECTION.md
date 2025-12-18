# YOLO Data Collection Feature

## Purpose
Use base YOLO11 for live object detection while capturing frames for custom dataset creation.

## Features
- [x] Base YOLO11n model (generic COCO objects)
- [ ] Live detection overlay on glasses stream
- [ ] Capture button to save frames with detections
- [ ] Auto-save frames when objects detected
- [ ] Export dataset (images + annotations)

## Data Flow
```
Glasses Stream → YOLO Detection → Display + Optional Capture
                                        ↓
                              Save to: Documents/YOLODataset/
                                        ↓
                              images/ + labels/ (YOLO format)
```

## Storage Format
```
YOLODataset/
├── images/
│   ├── frame_001.jpg
│   ├── frame_002.jpg
│   └── ...
├── labels/
│   ├── frame_001.txt  (YOLO format: class x y w h)
│   ├── frame_002.txt
│   └── ...
└── classes.txt
```

## Future: VLM Integration
- Add API call to Vision Language Model for:
  - Auto-labeling new objects
  - Verifying/correcting YOLO detections
  - Natural language queries about scene

## Usage
1. Stream from glasses
2. YOLO shows detected objects
3. When you see something to capture:
   - Tap capture button (or auto-capture on detection)
4. Frames saved with bounding box annotations
5. Export dataset for training new model
