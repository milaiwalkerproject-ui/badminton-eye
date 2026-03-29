# Technology Stack

**Project:** Badminton Eye
**Researched:** 2026-03-28

## Recommended Stack

### Core Platform

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Swift | 6.x | Primary language | Required for iOS/watchOS, modern concurrency, type safety | HIGH |
| SwiftUI | iOS 18+ / watchOS 11+ | UI framework | Declarative, shared code between iPhone/iPad/Watch, Apple's clear direction | HIGH |
| Xcode | 26 | IDE & build | Required for App Store submission from April 2026 | HIGH |

**Minimum deployment targets:** iOS 17, watchOS 10 (per PROJECT.md constraints). Build with iOS 18 SDK.

### Data Persistence & Sync

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| SwiftData | iOS 17+ | Local persistence | Modern, macro-based, native SwiftUI integration, production-ready as of iOS 18 | HIGH |
| CloudKit | Current | Cloud sync & user data | Free with Apple Developer account, native iCloud integration, no backend to build/maintain | HIGH |
| WatchConnectivity | Current | Real-time iPhone<->Watch sync | Only framework for direct device-to-device communication; 97%+ delivery within 1 second | HIGH |

**Architecture note:** Use SwiftData + CloudKit for persistent match history (syncs across user's devices). Use WatchConnectivity `sendMessage(_:replyHandler:)` for real-time score updates during active matches (low latency, works when both devices are reachable). Fall back to `transferUserInfo` for background delivery when Watch app is not foregrounded.

**CloudKit + watchOS caveat (MEDIUM confidence):** Multiple developer reports indicate SwiftData CloudKit sync to watchOS can be unreliable. Mitigation: use WatchConnectivity as the primary real-time channel and CloudKit as eventual-consistency backup. Test this early in development.

### Authentication

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| AuthenticationServices | iOS 17+ | Sign in with Apple | Required by Apple if offering any social auth; simplest for iOS-only app; no email/password infrastructure needed | HIGH |
| CloudKit identity | Current | User account binding | Implicit iCloud identity ties data to user with zero additional auth infrastructure | HIGH |

**Do NOT use Firebase Auth.** For an iOS-only app with Apple Sign In as the sole auth method, Firebase adds unnecessary complexity, a third-party dependency, and a separate user database. CloudKit identity + AuthenticationServices covers everything needed.

### Subscription & Billing

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| StoreKit 2 | iOS 17+ | Subscription management | Native async/await API, built-in receipt validation, SubscriptionStoreView for merchandising UI | HIGH |

**Do NOT use RevenueCat** for v1. Rationale:
- iOS-only app with a single subscription tier does not need cross-platform entitlement management
- StoreKit 2's native API is significantly simpler than StoreKit 1 (the main reason RevenueCat existed)
- SubscriptionStoreView and SubscriptionOfferView handle merchandising UI natively
- Saves $0-800+/month in RevenueCat fees
- If you later need A/B pricing experiments or analytics dashboards, RevenueCat can be added without rewriting purchase logic

**StoreKit 2 key requirements (iOS 18.2+):** Purchase methods now require a UI context parameter. Use `SubscriptionStoreView` for the subscription paywall -- it handles compliance, restore purchases, and merchandising automatically.

### Computer Vision / AI (Hawk Eye)

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Core ML | iOS 17+ | On-device ML inference | Apple's native ML runtime, optimized for Neural Engine, privacy-preserving | HIGH |
| Vision framework | iOS 17+ | Video frame analysis pipeline | Handles camera input, preprocessing, coordinates with Core ML models | HIGH |
| YOLO26 (Ultralytics) | Latest (Feb 2026) | Object detection model | Edge-optimized, NMS-free, Core ML export supported, best speed/accuracy for mobile | HIGH |
| Create ML | Current | Model fine-tuning | Train custom shuttle detection model with transfer learning (as few as 30-80 images per class) | MEDIUM |
| AVFoundation | iOS 17+ | Video capture & processing | Frame-by-frame video analysis from recorded court footage | HIGH |

**Model pipeline:**

1. **Training (offline, on Mac):** Use Ultralytics Python toolkit to train YOLO26 nano/small model on custom badminton court + shuttle dataset. Export to `.mlpackage` via `model.export(format='coreml')`.
2. **Inference (on-device):** Load `.mlpackage` with Core ML, feed video frames via Vision framework's `VNImageRequestHandler`. YOLO26 nano runs real-time on iPhone Neural Engine.
3. **Trajectory calculation:** Post-process detected shuttle positions across frames to compute trajectory, estimate landing point, render in/out determination.

**Why YOLO26 over YOLO11/YOLOv8:** YOLO26 (Sept 2025) is specifically optimized for edge devices, removes NMS post-processing (faster inference), and has improved Core ML export support with dynamic image shapes. Use the `yolo26n` (nano) variant for real-time performance.

**Why NOT a cloud-based model (e.g., sending frames to a server):**
- Latency: users expect near-instant replay analysis
- Cost: video frame processing at scale is expensive
- Privacy: court footage may contain bystanders
- Offline: many courts have poor connectivity

**Challenge: shuttle detection accuracy.** A badminton shuttle is small (often <15px in frame), moves at 200+ mph, and suffers severe motion blur. Mitigations:
- Recommend court-side tripod setup (documented in PROJECT.md)
- Train on diverse court/lighting conditions
- Use tiling approach for small object detection
- Display confidence indicators to users (not just binary in/out)
- This is the highest technical risk in the project -- prototype early

### Camera & Video

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| AVFoundation | iOS 17+ | Video recording & frame extraction | Full control over camera pipeline, frame-by-frame access for CV processing | HIGH |
| PhotosUI | iOS 17+ | Video picker from camera roll | For importing previously recorded match footage | HIGH |

### Testing

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Swift Testing | Xcode 16+ | Unit & integration tests | Modern macro-based assertions (#expect), parallel by default, Apple's direction | HIGH |
| XCTest | Current | UI tests & performance tests | Swift Testing doesn't yet support UI/performance testing; use XCTest for these | HIGH |
| StoreKit Testing | Xcode | Subscription testing | Local sandbox testing without TestFlight; configure via StoreKit Configuration File | HIGH |

**Strategy:** Write all new unit/integration tests with Swift Testing. Use XCTest only for UI tests and performance benchmarks. Both frameworks coexist in the same target.

### Monitoring & Analytics

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| OSLog | iOS 17+ | Structured logging | Native, zero-dependency, integrates with Console.app and Instruments | HIGH |
| MetricKit | iOS 17+ | Crash & performance reporting | Native, no third-party SDK, reports battery/performance/crash data | MEDIUM |

**Do NOT add third-party analytics SDKs for v1.** Apple's App Analytics in App Store Connect provides download, retention, and revenue data. Add TelemetryDeck or similar only if specific product analytics questions emerge post-launch.

### Architecture Libraries

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| swift-dependencies | Latest | Dependency injection | Lightweight, testable, Point-Free ecosystem, better than hand-rolled singletons | MEDIUM |
| swift-collections | Latest | Data structures | OrderedDictionary, Deque for match state management | MEDIUM |

## What NOT to Use

| Technology | Why Not |
|------------|---------|
| **Firebase** | Unnecessary for iOS-only app. CloudKit is free, native, requires no backend. Firebase adds SDK bloat, a Google dependency, and a separate auth system. |
| **RevenueCat** | Overkill for single-platform, single-tier subscription. StoreKit 2 handles this natively. Revisit only if adding Android or complex pricing experiments. |
| **Realm** | SwiftData is Apple's native solution, integrates with CloudKit out of the box. Realm adds a third-party dependency for no benefit. |
| **Core Data** | SwiftData is the modern replacement. For a greenfield iOS 17+ app, there is no reason to use Core Data directly. |
| **UIKit** | SwiftUI covers all UI needs for this app. No legacy code to integrate. watchOS requires SwiftUI anyway. |
| **Combine** | Swift Concurrency (async/await, AsyncSequence) replaces Combine for new code. Combine is maintenance-mode. |
| **MVVM with ObservableObject** | Use the `@Observable` macro (Observation framework, iOS 17+) instead. Simpler, better performance, no `@Published` boilerplate. |
| **Alamofire/networking libraries** | No REST API to call. CloudKit has its own API. URLSession handles any remaining HTTP needs. |
| **TensorFlow Lite** | Core ML is the native iOS inference runtime. TF Lite adds complexity with no benefit on Apple silicon. |
| **OpenCV** | Vision framework + Core ML covers all needed CV operations natively. OpenCV is a heavy C++ dependency. |

## Installation

```bash
# No package manager dependencies for core stack -- it's all Apple frameworks.

# Optional (via Swift Package Manager):
# swift-dependencies (Point-Free) - dependency injection
# swift-collections (Apple) - advanced data structures

# ML Model Training (Python, development machine only):
pip install ultralytics
yolo export model=yolo26n.pt format=coreml  # Produces .mlpackage
```

## Version Compatibility Matrix

| Component | Min iOS | Min watchOS | Notes |
|-----------|---------|-------------|-------|
| SwiftUI | 17 | 10 | Full feature set for this app |
| SwiftData | 17 | 10 | CloudKit sync improved in iOS 18 |
| StoreKit 2 | 17 | 10 | SubscriptionStoreView in iOS 17+ |
| AuthenticationServices | 17 | 10 | SignInWithAppleButton |
| Core ML | 17 | 10 | Neural Engine optimized |
| Vision | 17 | N/A | iPhone-only (Hawk Eye) |
| WatchConnectivity | 10 | 10 | Stable, well-established |
| Swift Testing | Xcode 16 | Xcode 16 | Coexists with XCTest |
| @Observable | 17 | 10 | Replaces ObservableObject |

## Sources

- [Apple Watch Connectivity Documentation](https://developer.apple.com/documentation/watchconnectivity)
- [SwiftData CloudKit Sync](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
- [StoreKit 2 Developer Page](https://developer.apple.com/storekit/)
- [StoreKit 2 WWDC25 Updates](https://dev.to/arshtechpro/wwdc-2025-whats-new-in-storekit-and-in-app-purchase-31if)
- [YOLO26 Ultralytics Docs](https://docs.ultralytics.com/models/yolo26/)
- [YOLO26 CoreML Export](https://docs.ultralytics.com/integrations/coreml/)
- [Ultralytics YOLO26 to Apple Devices via CoreML](https://www.ultralytics.com/blog/bringing-ultralytics-yolo11-to-apple-devices-via-coreml)
- [SwiftData vs Core Data 2025](https://www.hashstudioz.com/blog/swiftdata-vs-core-data-which-should-you-choose-in-2025/)
- [Swift Testing - Apple Developer](https://developer.apple.com/xcode/swift-testing/)
- [RevenueCat vs Native IAP](https://nativelaunch.dev/articles/compare/revenuecat-vs-native-iap)
- [Apple Vision Framework](https://developer.apple.com/documentation/vision)
- [Sign in with Apple - SwiftUI](https://developer.apple.com/documentation/AuthenticationServices/implementing-user-authentication-with-sign-in-with-apple)
