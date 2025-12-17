# YOLO Composable Architecture

> Design document for a flexible, composable YOLO detection system that supports multiple models, interpreters, and customizations.

## Overview

This architecture enables:
- **Multiple YOLO models** (poker, COCO, race classification, custom)
- **Model-agnostic detection** via Apple Vision framework
- **Pluggable interpreters** for domain-specific processing
- **Composable UI** that adapts to model type

---

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           PRESENTATION LAYER                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────┐  │
│  │ ModelPickerView │  │ BoundingBoxView │  │ Model-Specific Overlays │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
┌─────────────────────────────────────────────────────────────────────────┐
│                          INTERPRETER LAYER                               │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ DetectionInterpreter Protocol                                    │    │
│  │  ├── PokerHandInterpreter      → Hand rankings, card positions  │    │
│  │  ├── GenericObjectInterpreter  → Object counts, categories      │    │
│  │  ├── FaceAttributeInterpreter  → Demographics, attributes       │    │
│  │  └── PassthroughInterpreter    → No processing (default)        │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
┌─────────────────────────────────────────────────────────────────────────┐
│                          DETECTION LAYER                                 │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ YOLODetectionService                                             │    │
│  │  • Model-agnostic VNCoreMLRequest execution                      │    │
│  │  • Returns standardized [YOLODetection]                          │    │
│  │  • Handles throttling, async processing                          │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
┌───────────────────────────────────┴─────────────────────────────────────┐
│                            MODEL LAYER                                   │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ YOLOModelManager                                                 │    │
│  │  • Discovers bundled/local/remote models                         │    │
│  │  • Handles download, compilation, loading                        │    │
│  │  • Manages model lifecycle                                       │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ YOLOModelInfo                                                    │    │
│  │  • Source (bundled/local/remote)                                 │    │
│  │  • Specs (inputs, outputs, class labels)                         │    │
│  │  • Type hint (for interpreter selection)                         │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└───────────────────────────────────┬─────────────────────────────────────┘
                                    │
┌───────────────────────────────────┴─────────────────────────────────────┐
│                        PERSISTENCE LAYER (SwiftData)                     │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ ModelContainer                                                   │    │
│  │  • YOLOModelRecord   → Favorites, preferences, download history │    │
│  │  • DetectionSession  → Usage analytics, performance stats       │    │
│  │  • InterpreterConfig → Per-model interpreter settings           │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Core Components

### 1. Model Layer

#### `YOLOModelInfo`
Metadata container for any YOLO model.

```swift
struct YOLOModelInfo {
    let id: String
    let name: String
    let source: YOLOModelSource       // .bundled, .local, .remote
    let modelType: YOLOModelType?     // Optional type hint
    var classLabels: [String]?        // Known labels (auto-extracted)
}

enum YOLOModelType: String, Codable {
    case generic              // COCO-style object detection
    case poker                // Playing card detection
    case faceClassification   // Face attribute detection
    case custom               // User-defined
}
```

#### `YOLOModelManager`
Manages model lifecycle: discovery, download, compilation, loading.

| Method | Purpose |
|--------|---------|
| `discoverModels()` | Find bundled, local, and featured models |
| `downloadModel(_:)` | Download and compile remote models |
| `loadModel(_:)` | Load model into VNCoreMLModel |
| `deleteModel(_:)` | Remove downloaded models |

---

### 2. Detection Layer

#### `YOLODetection`
Standardized detection result from any YOLO model.

```swift
struct YOLODetection {
    let label: String        // Raw class label from model
    let confidence: Float    // 0.0 - 1.0
    let boundingBox: CGRect  // Normalized coordinates
}
```

#### `YOLODetectionService`
Model-agnostic detection execution.

- Accepts any `VNCoreMLModel`
- Uses Vision framework for inference
- Returns `[YOLODetection]` regardless of model type
- Handles throttling (configurable FPS)

---

### 3. Interpreter Layer (Future)

#### `DetectionInterpreter` Protocol

```swift
protocol DetectionInterpreter {
    associatedtype Result
    
    static var supportedModelTypes: Set<YOLOModelType> { get }
    
    func interpret(_ detections: [YOLODetection]) -> Result
}
```

#### Built-in Interpreters

| Interpreter | Model Type | Output |
|-------------|------------|--------|
| `PassthroughInterpreter` | `.generic` | Raw detections |
| `PokerHandInterpreter` | `.poker` | `PokerHand` with ranking |
| `ObjectCounterInterpreter` | `.generic` | Grouped object counts |
| `FaceAttributeInterpreter` | `.faceClassification` | Face attributes |

#### Interpreter Registry

```swift
class InterpreterRegistry {
    static func interpreter(for modelType: YOLOModelType) -> any DetectionInterpreter
}
```

---

### 4. Presentation Layer

#### Composable SwiftUI Views

| View | Purpose |
|------|---------|
| `ModelPickerView` | Model selection, download, management |
| `DetectionOverlayView` | Bounding box rendering |
| `PokerCardOverlay` | Specialized poker card display |
| `DetectionStatsView` | FPS, inference time, detection count |

Views receive interpreted results via `@Published` properties and adapt their display accordingly.

---

## Data Flow

```
┌──────────────┐     ┌───────────────────┐     ┌──────────────────┐
│ Video Frame  │────▶│ YOLODetectionSvc  │────▶│ [YOLODetection]  │
│ (UIImage)    │     │ (VNCoreMLRequest) │     │ (raw labels)     │
└──────────────┘     └───────────────────┘     └────────┬─────────┘
                                                        │
                                                        ▼
┌──────────────┐     ┌───────────────────┐     ┌──────────────────┐
│ Overlay View │◀────│ Interpreter       │◀────│ Interpreter      │
│ (adapted UI) │     │ (model-specific)  │     │ Registry lookup  │
└──────────────┘     └───────────────────┘     └──────────────────┘
```

---

## Extension Points

### Adding a New Model Type

1. Add case to `YOLOModelType` enum
2. Create interpreter implementing `DetectionInterpreter`
3. Register interpreter in `InterpreterRegistry`
4. (Optional) Create specialized overlay view

### Adding a Featured Model

In `YOLOModelManager.featuredModels()`:

```swift
YOLOModelInfo(
    id: "featured_my_model",
    name: "My Custom Model",
    source: .remote(url: "https://..."),
    modelType: .custom
)
```

---

## Design Principles

| Principle | Implementation |
|-----------|----------------|
| **Single Responsibility** | Each layer has one job |
| **Open/Closed** | Add interpreters without modifying core |
| **Dependency Inversion** | Views depend on protocols, not concrete types |
| **Protocol-Oriented** | Interpreters are protocol-based |

---

## Persistence Layer (Future - SwiftData)

### Overview

SwiftData provides persistence for model metadata, user preferences, and analytics. This layer sits alongside the Model Layer and is accessed by both `YOLOModelManager` and the Presentation Layer.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         PERSISTENCE LAYER                                │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ SwiftData ModelContainer                                         │    │
│  │  • YOLOModelRecord - Model metadata, favorites, settings         │    │
│  │  • DetectionSession - Usage analytics, performance stats         │    │
│  │  • InterpreterConfig - Per-model interpreter customization       │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

### SwiftData Models

#### `YOLOModelRecord`
Persistent metadata for each model.

```swift
@Model
class YOLOModelRecord {
    @Attribute(.unique) var id: String
    var name: String
    var modelType: String               // .poker, .generic, .custom
    var remoteURL: String?              // Source URL for remote models
    var localPath: String?              // Path to downloaded .mlmodelc
    
    // User preferences
    var isFavorite: Bool = false
    var confidenceThreshold: Float = 0.5
    var isHidden: Bool = false          // User can hide models
    
    // Metadata
    var downloadDate: Date?
    var lastUsedDate: Date?
    var usageCount: Int = 0
    
    // Interpreter configuration (JSON)
    var interpreterConfigJSON: String?
}
```

#### `DetectionSession`
Analytics for usage tracking and performance monitoring.

```swift
@Model
class DetectionSession {
    var id: UUID = UUID()
    var startDate: Date
    var endDate: Date?
    var durationSeconds: Double?
    
    // Performance
    var totalDetections: Int = 0
    var avgInferenceTimeMs: Double = 0
    var framesProcessed: Int = 0
    
    // Context
    @Relationship var model: YOLOModelRecord?
}
```

#### `InterpreterConfig`
Per-model interpreter customization.

```swift
@Model
class InterpreterConfig {
    @Attribute(.unique) var modelId: String
    
    // Common settings
    var nmsThreshold: Float = 0.45
    var maxDetections: Int = 100
    
    // Model-specific settings (JSON blob)
    var customSettingsJSON: String?
    
    @Relationship var model: YOLOModelRecord?
}
```

### Integration Pattern

```swift
@MainActor
class YOLOModelManager: ObservableObject {
    private let modelContext: ModelContext
    
    // On model download, persist record
    func downloadModel(_ model: YOLOModelInfo) async {
        // ... download logic ...
        
        // Persist to SwiftData
        let record = YOLOModelRecord(id: model.id, name: model.name, ...)
        record.downloadDate = Date()
        modelContext.insert(record)
    }
    
    // On model load, update usage stats
    func loadModel(_ model: YOLOModelInfo) async throws {
        // ... load logic ...
        
        // Update SwiftData
        if let record = fetchRecord(for: model.id) {
            record.lastUsedDate = Date()
            record.usageCount += 1
        }
    }
}
```

### User-Facing Features Enabled

| Feature | SwiftData Backing |
|---------|-------------------|
| **Favorites** | `YOLOModelRecord.isFavorite` |
| **Recently Used** | Sort by `lastUsedDate` |
| **Per-model thresholds** | `YOLOModelRecord.confidenceThreshold` |
| **Usage analytics** | `DetectionSession` aggregation |

<!-- FUTURE: CloudKit Sync (commented out for now)

### CloudKit Consideration

SwiftData supports CloudKit sync out of the box. To enable:

```swift
let schema = Schema([YOLOModelRecord.self, DetectionSession.self])
let config = ModelConfiguration(schema: schema, cloudKitDatabase: .private("iCloud.com.app.yolo"))
let container = try ModelContainer(for: schema, configurations: config)
```

This would sync favorites, preferences, and download history across user's devices.

-->

---

## Current State vs Future

| Component | Current | Future |
|-----------|---------|--------|
| Model Layer | ✅ Complete | Add model type hints |
| Detection Layer | ✅ Complete | — |
| Interpreter Layer | ❌ Not implemented | Full interpreter system |
| Presentation Layer | ✅ Basic overlays | Model-adaptive views |
| Persistence Layer | ❌ Not implemented | SwiftData integration |

---

## Related Files

- [YOLOModelInfo.swift](file:///samples/CameraAccess/CameraAccess/Features/yolo/Models/YOLOModelInfo.swift)
- [YOLOModelManager.swift](file:///samples/CameraAccess/CameraAccess/Features/yolo/Services/YOLOModelManager.swift)
- [YOLODetectionService.swift](file:///samples/CameraAccess/CameraAccess/Features/yolo/Services/YOLODetectionService.swift)
- [ModelPickerView.swift](file:///samples/CameraAccess/CameraAccess/GUI/Views/Components/ModelPickerView.swift)
