# Architecture Patterns

**Domain:** Native iOS + watchOS badminton scoring app with real-time sync and AI computer vision
**Researched:** 2026-03-28

## Recommended Architecture

### High-Level System Diagram

```
+--------------------------------------------------+
|                   Apple Cloud                     |
|  +-------------+  +------------+  +------------+ |
|  | CloudKit    |  | StoreKit   |  | Apple Auth | |
|  | (SwiftData  |  | Server     |  | (Sign In   | |
|  |  Sync)      |  | (Receipts) |  |  w/ Apple) | |
|  +------+------+  +------+-----+  +-----+------+ |
+---------|-----------------|--------------|---------+
          |                 |              |
+---------v-----------------v--------------v---------+
|                 iPhone / iPad App                   |
|                                                     |
|  +------------------+    +----------------------+   |
|  |  Scoring Engine   |    |  Hawk Eye Pipeline  |   |
|  |  (Match State     |    |  (Video Capture ->  |   |
|  |   Machine)        |    |   Court Detection ->|   |
|  |                   |    |   Shuttle Tracking ->|   |
|  +--------+----------+    |   Landing Calc ->   |   |
|           |               |   Visual Render)    |   |
|           |               +----------+----------+   |
|  +--------v----------+              |               |
|  | SwiftData Layer    |              |               |
|  | (Matches, Players, |   +---------v-----------+   |
|  |  Stats, History)   |   | Core ML Models      |   |
|  +--------+-----------+   | - Court Detector     |   |
|           |               | - Shuttle Tracker    |   |
|           |               |   (TrackNet/YOLO)    |   |
|  +--------v----------+   +---------+-----------+   |
|  | WatchConnectivity  |            |               |
|  | Manager (Singleton)|   +--------v-----------+   |
|  +--------+-----------+   | Vision Framework   |   |
|           |               | (Video frame        |   |
+-----------+---------------| processing)         |   |
            |               +--------------------+   |
+-----------v-----------------------------------+     |
|              Apple Watch App                  |     |
|                                               |     |
|  +------------------+  +------------------+   |     |
|  | Score Display     |  | Score Input      |   |     |
|  | (Glanceable UI)   |  | (Tap to score)   |   |     |
|  +------------------+  +------------------+   |     |
|                                               |     |
|  +------------------+                         |     |
|  | WatchConnectivity |                         |     |
|  | Session Delegate  |                         |     |
|  +------------------+                         |     |
+-----------------------------------------------+     |
                                                      |
```

### Component Boundaries

| Component | Responsibility | Communicates With | Platform |
|-----------|---------------|-------------------|----------|
| **Scoring Engine** | BWF rule enforcement, match state machine (points, games, sets, serve rotation, deuce logic) | SwiftData Layer, WatchConnectivity Manager | iOS (shared logic) |
| **SwiftData Layer** | Persistence of matches, players, stats; auto-sync to CloudKit | Scoring Engine, CloudKit (automatic) | iOS |
| **WatchConnectivity Manager** | Bidirectional real-time score sync between iPhone and Watch | Scoring Engine, Watch Score Display/Input | iOS + watchOS |
| **Hawk Eye Pipeline** | Orchestrates video analysis: capture, court detection, shuttle tracking, landing calculation, visual rendering | Core ML Models, Vision Framework, Camera | iOS only |
| **Core ML Models** | On-device inference for court line detection and shuttle tracking | Hawk Eye Pipeline | iOS only |
| **Auth Manager** | Apple Sign-In, session state, entitlement checks | StoreKit Manager, CloudKit | iOS |
| **StoreKit Manager** | Subscription lifecycle, receipt validation, premium feature gating | Auth Manager, Hawk Eye Pipeline (gate) | iOS |
| **Watch Score Display** | Glanceable current score, game state, serving side | WatchConnectivity Session | watchOS |
| **Watch Score Input** | Minimal-tap scoring interface | WatchConnectivity Session, Scoring Engine (via message) | watchOS |
| **Stats Engine** | Win/loss records, performance analytics, match breakdowns | SwiftData Layer | iOS |
| **Export/Share Module** | CSV/PDF generation, social sharing | SwiftData Layer, UIActivityViewController | iOS |

## Data Flow

### 1. Live Match Scoring (Primary Flow)

```
User taps "Point" on iPhone OR Watch
        |
        v
WatchConnectivity sendMessage (if from Watch)
        |
        v
Scoring Engine validates against BWF rules
  - Checks current game state
  - Applies point (handles deuce, game point, match point)
  - Updates serve side and server rotation
        |
        v
SwiftData persists updated MatchState
  - CloudKit auto-syncs to iCloud (background)
        |
        v
WatchConnectivity sends updated state to Watch
  - Uses sendMessage for real-time (both apps active)
  - Falls back to updateApplicationContext (Watch app inactive)
        |
        v
Watch UI updates reactively via @Observable
```

**Key design decision:** The Scoring Engine is the single source of truth. Even when scoring from the Watch, the message goes to the iPhone's Scoring Engine for validation, then the confirmed state syncs back. This prevents split-brain where both devices calculate independently and diverge.

**Fallback when iPhone is unreachable:** The Watch app should maintain a lightweight local scoring capability for when the iPhone is not reachable (`WCSession.isReachable == false`). Queue state changes and reconcile when reconnected.

### 2. Hawk Eye Challenge Flow

```
User taps "Challenge" in match view
        |
        v
Camera captures video clip (AVCaptureSession)
  - 3-5 seconds of footage around the disputed shot
  - 120fps or 240fps slow-motion preferred
        |
        v
Court Detection (runs once per challenge)
  - Vision framework line detection (VNDetectContoursRequest)
  - OR Core ML court keypoint model
  - Outputs: court boundary coordinates, homography matrix
        |
        v
Shuttle Tracking (per-frame)
  - Core ML model (TrackNet-style or YOLO-based)
  - Processes consecutive frames to track shuttle trajectory
  - Outputs: sequence of (x, y) positions in image space
        |
        v
Trajectory Calculation
  - Apply homography to map image coords -> court coords
  - Fit trajectory curve (quadratic/physics-based)
  - Kalman filter for noise smoothing
  - Calculate predicted landing point
        |
        v
In/Out Determination
  - Compare landing point against court boundary model
  - Calculate margin (distance from line)
  - Assign confidence score based on video quality, angle
        |
        v
Visual Rendering
  - Overlay trajectory arc on court diagram
  - Show landing spot with in/out indicator
  - Display confidence percentage
  - Animate like broadcast Hawk-Eye replay
        |
        v
Result stored in MatchEvent linked to current rally
```

### 3. Data Sync Flow

```
SwiftData @Model objects
        |
        v  (automatic via NSPersistentCloudKitContainer)
CloudKit Private Database
        |
        v  (push notification on change)
Other devices signed into same Apple ID
        |
        v
SwiftData merges incoming CKRecords
```

**Constraints for CloudKit sync:**
- No `@Attribute(.unique)` on synced properties
- All properties need defaults or must be optional
- Relationships must be optional
- Only private database (no sharing between users in v1)

## Patterns to Follow

### Pattern 1: Observable State Machine for Match Scoring

**What:** Model the match as an explicit state machine with `@Observable` for reactive SwiftUI updates.
**When:** All match scoring logic.
**Why:** BWF scoring has well-defined states (playing, deuce, game point, match point, complete). A state machine prevents invalid transitions and makes the Watch sync simpler -- just sync the state, not individual actions.

```swift
@Observable
final class MatchState {
    var currentGame: Int = 1
    var scores: (home: Int, away: Int) = (0, 0)
    var gameScores: [(home: Int, away: Int)] = []
    var servingSide: ServingSide = .right
    var server: Player
    var phase: MatchPhase = .playing // .playing, .deuce, .gamePoint, .matchPoint, .complete

    func scorePoint(for side: Side) -> MatchEvent {
        // Validate and transition state
        // Return event for history
    }
}
```

### Pattern 2: WatchConnectivity Singleton with Message Queue

**What:** A single `WCSessionDelegate` manager that handles all communication, with message queuing for reliability.
**When:** All iPhone <-> Watch communication.
**Why:** WCSession requires a singleton delegate. Message delivery is not guaranteed when the counterpart app is not reachable. Queue messages and replay on reconnection.

```swift
final class WatchSyncManager: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSyncManager()

    func sendScoreUpdate(_ state: MatchState) {
        let payload = state.toDictionary()
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil)
        } else {
            // Fallback: application context (latest state wins)
            try? WCSession.default.updateApplicationContext(payload)
        }
    }
}
```

### Pattern 3: Pipeline Architecture for Hawk Eye

**What:** Chain of processing stages, each with clear input/output contracts.
**When:** All Hawk Eye video analysis.
**Why:** Each stage (court detection, tracking, trajectory calc, rendering) has different performance characteristics and can be developed/tested independently. Court detection can be cached across frames. Shuttle tracking runs per-frame. Rendering is purely presentational.

### Pattern 4: SwiftData with Lightweight View Models

**What:** Use SwiftData `@Model` for persistence, but wrap match logic in `@Observable` view models rather than putting business logic in models.
**When:** Anywhere business logic meets persistence.
**Why:** SwiftData models handle persistence and CloudKit sync automatically. But scoring rules, stat calculations, and export logic belong in dedicated services, not in `@Model` classes. This keeps models lean and sync-friendly.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Dual Independent Scoring Engines

**What:** Running full scoring logic on both iPhone and Watch independently.
**Why bad:** Inevitable state divergence. Two devices calculating points independently will disagree at deuce, game transitions, or serve rotation. Debugging sync conflicts is a nightmare.
**Instead:** Single source of truth on iPhone. Watch sends intents ("user tapped point for Team A"), iPhone processes and sends back confirmed state. Watch maintains read-only local copy for display, with minimal offline fallback.

### Anti-Pattern 2: Cloud-First Hawk Eye Processing

**What:** Uploading video to a server for CV processing.
**Why bad:** Latency (users want instant replay feel), bandwidth costs, server infrastructure to maintain, privacy concerns with court-side video, and it fails offline. The whole appeal is instant, on-device analysis.
**Instead:** On-device Core ML inference. Modern iPhones (A15+) have Neural Engine capable of running YOLO/TrackNet models at real-time speeds. Keep everything local.

### Anti-Pattern 3: @Attribute(.unique) in Synced Models

**What:** Using unique constraints on SwiftData models that sync to CloudKit.
**Why bad:** CloudKit does not support unique constraints. Sync will silently fail or produce duplicates.
**Instead:** Use UUID-based identifiers without the `.unique` attribute. Handle deduplication in application logic if needed.

### Anti-Pattern 4: Complex Watch UI

**What:** Building feature-rich screens on watchOS with multi-step flows.
**Why bad:** Watch screen is tiny, interactions should be 1-2 taps max. Complex UIs frustrate users mid-game.
**Instead:** Watch shows: current score, game number, serve side, and two large tap targets (point for Team A / Team B). That is the entire Watch UI during a match.

## Component Build Order (Dependencies)

The architecture has clear dependency chains that dictate build order:

### Phase 1: Foundation (no dependencies)
1. **SwiftData Models** -- Match, Player, Game, Rally data models
2. **Scoring Engine** -- BWF rule logic, state machine (can be built and tested in isolation with unit tests)
3. **Basic iOS UI** -- Match creation, score display, history list

### Phase 2: Watch Integration (depends on Phase 1)
4. **WatchConnectivity Manager** -- Requires Scoring Engine to exist
5. **watchOS App** -- Score display and input, requires WatchConnectivity Manager
6. **Offline Watch Fallback** -- Queue and reconciliation logic

### Phase 3: Cloud and Auth (depends on Phase 1)
7. **Apple Sign-In** -- Auth flow
8. **CloudKit Sync** -- Enable on SwiftData models (requires models to follow CloudKit constraints from the start -- plan this in Phase 1)
9. **StoreKit Subscriptions** -- Premium gating

### Phase 4: Hawk Eye (depends on Phase 1 for match context, otherwise independent)
10. **Court Detection Model** -- Train/convert Core ML model for court line keypoints
11. **Shuttle Tracking Model** -- Train/convert TrackNet or YOLO-based tracker
12. **Hawk Eye Pipeline** -- Integrate camera capture, court detection, tracking, trajectory calc
13. **Visual Rendering** -- Animated replay overlay showing trajectory and landing
14. **Challenge Integration** -- Wire into match flow, store results

### Phase 5: Polish (depends on all above)
15. **Stats Engine** -- Aggregate match data into player profiles
16. **Export/Share** -- CSV/PDF generation, social sharing
17. **Onboarding and UX polish**

**Critical dependency note:** CloudKit sync constraints (no `.unique`, optional relationships, default values) must be designed into the SwiftData models from Phase 1, even though CloudKit is enabled in Phase 3. Retrofitting these constraints later causes painful migrations.

## Scalability Considerations

| Concern | At launch (100 users) | At 10K users | At 100K users |
|---------|----------------------|--------------|---------------|
| **Data sync** | CloudKit free tier sufficient | CloudKit scales automatically; monitor request limits | May need to batch writes, optimize model granularity |
| **Hawk Eye models** | Ship with app bundle | Ship with app bundle | Ship with app bundle (on-device, no server scaling needed) |
| **Match history** | SQLite handles thousands of records fine | SwiftData/SQLite fine to 100K+ records | Add pagination, lazy loading for old matches |
| **Subscription validation** | StoreKit 2 server-side validation | Same | Same -- Apple handles scale |
| **Model updates** | App Store updates | Consider on-demand Core ML model download for faster iteration | Background model updates via CloudKit assets or CDN |

## Technology-Specific Architecture Notes

### WatchConnectivity Communication Strategy

| Method | Use Case | Guarantees |
|--------|----------|------------|
| `sendMessage` | Real-time score updates (both apps active) | Immediate, but fails if counterpart not reachable |
| `updateApplicationContext` | Latest match state fallback | Queued, only latest value kept, delivered when Watch app opens |
| `transferUserInfo` | Match completion events, stats updates | Queued FIFO, guaranteed delivery eventually |

Use `sendMessage` as primary during active matches. Always update `applicationContext` as fallback so the Watch has latest state even if it was backgrounded.

### Core ML Model Architecture for Hawk Eye

**Recommended approach:** Hybrid pipeline with two specialized models.

1. **Court Detector** -- Keypoint detection model (lighter weight, runs once per challenge)
   - Input: Single video frame (the clearest frame)
   - Output: Court corner and line intersection coordinates
   - Architecture: MobileNet backbone with keypoint head
   - Convert to Core ML via `coremltools`

2. **Shuttle Tracker** -- Object detection + tracking across frames
   - Input: Sequence of 3 consecutive frames (following TrackNet pattern)
   - Output: Heatmap of shuttle position per frame
   - Architecture: TrackNet (VGG16 encoder + DeconvNet decoder) or YOLOv8-nano
   - Must run at 30+ fps inference on Neural Engine
   - Convert via `coremltools` from PyTorch

**Training data:** Use publicly available badminton datasets (ShuttleSet, TrackNet dataset from research papers). Fine-tune on self-collected data for accuracy improvement.

**Model size budget:** Keep combined models under 50MB to avoid App Store download size concerns. MobileNet court detector ~5MB, shuttle tracker ~20-40MB.

## Sources

- [Watch Connectivity - Apple Developer Documentation](https://developer.apple.com/documentation/watchconnectivity)
- [WatchConnectivity Data Sync - Medium](https://medium.com/@sheik25bareeth/data-synchronization-between-ios-and-watchos-using-watchconnectivity-009a3064e12a)
- [Building iOS/Watch Communication with SwiftUI - Medium](https://gauravtakjaipur.medium.com/building-ios-apple-watch-communication-with-swiftui-and-watchconnectivity-67c25008d15e)
- [Vision Framework - Apple Developer Documentation](https://developer.apple.com/documentation/vision)
- [Real-time Object Detection in iOS Using Vision Framework](https://medium.com/@authfy/real-time-object-detection-in-ios-using-vision-framework-and-swiftui-e77b1523b5fe)
- [Spyrosoft: Instant Review System for Badminton CV](https://spyro-soft.com/blog/artificial-intelligence-machine-learning/instant-review-system-for-badminton-computer-vision-use-case)
- [TrackNet Shuttle Trajectory from Monocular Video - Stanford](https://cs.stanford.edu/people/paulliu/files/cvpr-2022.pdf)
- [YOLO-based Shuttlecock Detection - ScienceDirect](https://www.sciencedirect.com/science/article/abs/pii/S0957417420306436)
- [YO-CSA-T Real-time Badminton Tracking - arXiv](https://arxiv.org/pdf/2501.06472)
- [Hawk-Eye Technology - Wikipedia](https://en.wikipedia.org/wiki/Hawk-Eye)
- [SwiftData with CloudKit - Hacking with Swift](https://www.hackingwithswift.com/books/ios-swiftui/syncing-swiftdata-with-cloudkit)
- [SwiftData Architecture Patterns 2025 - AzamSharp](https://azamsharp.com/2025/03/28/swiftdata-architecture-patterns-and-practices.html)
- [Core ML Deployment On-Device vs Cloud](https://clouddevs.com/ios/coreml-model-deployment/)
- [WWDC24: Deploy ML Models On-Device with Core ML](https://developer.apple.com/videos/play/wwdc2024/10161/)
- [Core ML Export for YOLO Models - Ultralytics](https://docs.ultralytics.com/integrations/coreml/)
