# Poker Detection - Implementation Status

Real-time poker card detection for Meta smart glasses using YOLO11.

## ✅ What's Working

| Feature | Description |
|---------|-------------|
| Card Detection | Detects cards in camera frame |
| Card Identification | Identifies rank + suit (10♥, A♠, etc.) |
| Readable Labels | 32pt bold text on suit-colored background |
| Hand Evaluation | Evaluates poker hands (High Card → Royal Flush) |
| NMS Filtering | Reduces duplicate bounding boxes |
| Hand Result UI | Glass morphism header with expandable card list |

## ❌ Not Implemented Yet

| Feature | Description |
|---------|-------------|
| Dual-Corner Deduplication | Same card detected at both corners |
| Spatial Reasoning | Classify hole cards vs community cards (see below) |
| Detection Smoothing | Persistence buffer to reduce flickering |
| Position Smoothing | Lerp bounding box positions for stability |
| Hysteresis Thresholds | Different enter/exit confidence thresholds |
| Win Probability | Calculate odds based on visible cards |
| Session Tracking | Hand history and statistics |

### Spatial Reasoning - Engineering Breakdown

**Naive approach (wrong):**
> "If Y > 60%, it's a hole card"

**Correct approach (stateful detection):**
1. First detect **2 cards grouped together** near player → candidate hole cards
2. Confirm grouping (close proximity, similar Y position)
3. Lock those as "hole cards" for this hand
4. Then look for **3-5 cards grouped elsewhere** → community cards
5. Validate: same card can't appear in both groups
6. State persists until hand reset (new shuffle detected)

**Key insight:** We must detect the hole cards FIRST before assuming there's a community area.

### Prediction Stability Problem

**The issue:** Model predictions flicker between cards, even at same location.

```
Frame 1: "10♥" (correct)
Frame 2: "6♥"  (wrong - flickered)
Frame 3: "10♥" (correct)
Frame 4: "10♥" (correct)
Frame 5: "J♦"  (wrong - noise)
Frame 6: "10♥" (correct)
```

Even 95% accuracy = 1 wrong prediction every 20 frames = visible flicker at 30fps.

**Solution: Temporal Voting**

Track predictions at each position over time:
```
Position (x,y) over last 10 frames:
  10♥: 8 times (80%) → OUTPUT THIS
  6♥:  1 time  (10%)
  J♦:  1 time  (10%)
```

Only change displayed card when a **different** card wins majority of recent frames.

### The Missing Layer: Aggregation (Layer 2.5)

```
Layer 2: Recognition → "I see 10♥ at (x,y)"
Layer 2.5: Aggregation → Stable, grouped, validated cards ← MISSING
Layer 3: Understanding → "Player has 10♥, 6♥"
```

**Layer 2.5 Components:**
1. **Temporal voting** - Consensus across frames before showing
2. **Position tracking** - Group predictions by spatial location
3. **Deduplication** - Same card at two corners = one card
4. **Grouping** - Cluster into hole vs community
5. **Validation** - No duplicate cards across groups
6. **Hysteresis** - Harder to exit than enter (sticky labels)

## Key Files

|------|---------|
| `YOLOOutputDecoder.swift` | Parses YOLO tensor `[1, 56, 8400]` with stride indexing |
| `PokerDetectionOverlay.swift` | Card labels and hand result UI |
| `PokerDetectionService.swift` | Vision framework integration |
| `PokerCard.swift` | Card model and label parsing |

## Game Structure (Texas Hold'em)

- **2 hole cards** - Player's private hand (lower frame)
- **3-5 community cards** - Center table (upper frame)
  - Flop: 3, Turn: 4, River: 5

## Known Issues

### Dual-Corner Detection
Each card has rank/suit in two corners. YOLO may detect same card twice.
**Solution:** Card-level grouping by class + distance threshold.

### Label Flickering
Detections come/go each frame causing labels to flash.
**Solution:** Persistence buffer (keep visible for 5-10 frames after last detection).

## Console Output

```
🔍 YOLO Decoder: MultiArray shape = [1, 56, 8400]
🔍 YOLO Decoder: 56 features, 8400 predictions
🔍 YOLO Decoder: 15 raw detections above threshold
🔍 YOLO Decoder: 3 after NMS
🔍 Decoded: 6♥ (76%)
🔍 Decoded: 10♥ (81%)
```
