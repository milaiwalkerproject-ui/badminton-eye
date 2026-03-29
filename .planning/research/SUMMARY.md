# Project Research Summary

**Project:** Badminton Eye
**Domain:** Native iOS + watchOS sports scoring app with AI computer vision
**Researched:** 2026-03-28
**Confidence:** HIGH (stack, features, architecture) / MEDIUM (Hawk Eye accuracy)

## Executive Summary

Badminton Eye is a native iOS + Apple Watch badminton scoring app whose primary differentiator is an AI-powered "Hawk Eye" line-calling system -- a feature no consumer badminton app currently offers. The research confirms that the correct approach is an all-Apple-native stack (Swift 6, SwiftUI, SwiftData, CloudKit, Core ML) with zero third-party backend dependencies. Every major technology choice -- persistence, auth, subscriptions, ML inference -- has a first-party Apple solution that is simpler, cheaper, and better integrated than any alternative. The competitive landscape shows multiple basic scoring apps but none offering consumer-grade AI line-calling, validating the differentiation strategy.

The recommended build strategy is to ship core scoring with Apple Watch sync first, then layer on cloud sync and social features, and finally add the Hawk Eye AI as the premium upsell. This order de-risks the business: if Hawk Eye accuracy proves insufficient (a real possibility with single-camera detection), the scoring app still delivers standalone value. The scoring engine must be a pure state machine with exhaustive unit tests from day one, and the SwiftData models must be designed with CloudKit constraints (optional properties, no unique attributes, default values) from the start even though cloud sync activates later.

The two highest risks are (1) WatchConnectivity unreliability during live matches and (2) single-camera shuttle tracking accuracy. The first is mitigated by using `updateApplicationContext` as the primary transport and persisting state after every single point. The second is mitigated by framing Hawk Eye as "AI-assisted replay" with confidence indicators rather than binary in/out verdicts, requiring tripod setup, and prototyping early with real court footage before investing in the full pipeline.

## Key Findings

### Recommended Stack

The stack is 100% Apple-native for the core product. No Firebase, no RevenueCat, no Realm, no UIKit, no Combine. This is a greenfield iOS 17+ / watchOS 10+ app that should use the latest Apple frameworks without backward-compatibility baggage. The only external tool is the Ultralytics YOLO26 model (trained in Python, exported to Core ML `.mlpackage` for on-device inference).

**Core technologies:**
- **Swift 6 + SwiftUI**: Primary language and UI for both iOS and watchOS; use `@Observable` macro, not `ObservableObject`
- **SwiftData + CloudKit**: Local persistence with automatic iCloud sync; no backend to build or maintain
- **WatchConnectivity**: Real-time bidirectional iPhone-Watch communication; the only viable framework for direct device sync
- **StoreKit 2**: Native subscription management with built-in receipt validation and `SubscriptionStoreView` for compliant paywall UI
- **Core ML + Vision + YOLO26 nano**: On-device ML inference for shuttle detection; privacy-preserving, works offline, optimized for Neural Engine
- **AuthenticationServices**: Apple Sign-In as sole auth method; no email/password infrastructure needed

**What NOT to use:** Firebase (unnecessary for iOS-only), RevenueCat (overkill for single-tier subscription), Realm/Core Data (SwiftData replaces both), UIKit/Combine (SwiftUI + async/await replace both), TensorFlow Lite/OpenCV (Core ML + Vision are native and superior on Apple silicon).

**Critical version note:** Target iOS 17 / watchOS 10 minimum. Build with iOS 18 SDK via Xcode 26. StoreKit 2 purchase methods require UI context parameter on iOS 18.2+.

### Expected Features

**Must have (table stakes):**
- BWF 21-point rally scoring (singles, doubles, mixed) with deuce and 30-point cap
- One-tap score increment with undo (minimum 5 levels deep)
- Service side and server tracking including doubles rotation
- Apple Watch score display and input with real-time iPhone sync
- Match history with local persistence
- Player profiles with saved players and cumulative W/L records
- Full offline operation for all core scoring

**Should have (differentiators):**
- Hawk Eye AI challenge system with visual trajectory replay and confidence indicators
- Court calibration via manual corner marking (homography for coordinate mapping)
- Apple Watch workout integration (HealthKit, Activity Rings)
- Live Activity on iPhone lock screen / Dynamic Island
- Head-to-head records and advanced match statistics
- Score announcements (voice/haptic)
- Share match results as images; export CSV/PDF

**Defer indefinitely:**
- Tournament bracket management (separate domain; let users export to dedicated tools)
- Coaching / training drills (different user mindset; dilutes product identity)
- Real-time multiplayer / online matches (badminton is played in person)
- Multi-sport support (sport-specific is a strength, not a limitation)
- Ad-supported free tier (ads during active play destroy UX; use freemium instead)

### Architecture Approach

The architecture follows a single-source-of-truth pattern: the iPhone's Scoring Engine owns all match state. The Watch sends scoring intents, the iPhone validates them against BWF rules, and confirmed state syncs back. This prevents split-brain where two devices calculate independently and diverge. The Hawk Eye feature is a separate pipeline (camera capture, court detection, shuttle tracking, trajectory calculation, visual rendering) that connects to the match context but is architecturally independent -- enabling parallel development.

**Major components:**
1. **Scoring Engine** -- Pure state machine enforcing BWF rules; testable in isolation with zero UI dependencies
2. **WatchConnectivity Manager** -- Singleton with message queue; `applicationContext` as primary transport, `sendMessage` as fast path when reachable
3. **SwiftData Layer** -- Persistence with automatic CloudKit sync; all models designed for CloudKit constraints from day one
4. **Hawk Eye Pipeline** -- Five-stage chain: video capture, court detection, shuttle tracking, trajectory calculation, visual rendering
5. **Core ML Models** -- Court detector (~5MB MobileNet backbone) + shuttle tracker (~20-40MB YOLO26 nano); combined under 50MB
6. **StoreKit Manager** -- Subscription lifecycle and premium feature gating via `Transaction.currentEntitlements`

### Critical Pitfalls

1. **WatchConnectivity drops messages during live play** -- Use `updateApplicationContext` as primary transport (latest score state always arrives on reconnection); persist state to local storage after every point; implement lightweight Watch-side fallback for when iPhone is unreachable
2. **Single-camera Hawk Eye accuracy is fundamentally limited** -- Professional 14-camera systems achieve only 62% autonomous accuracy; reframe as "AI-assisted replay" with confidence zones, not binary verdicts; prototype with 50+ real court videos before building the full pipeline; set a confidence threshold below which the system says "inconclusive"
3. **CloudKit/SwiftData sync fails silently in production** -- Deploy schema to CloudKit Production environment before App Store submission; make all SwiftData properties optional or defaulted from day one; never rename entities post-release; implement visible sync status indicator
4. **BWF scoring edge cases corrupt match state** -- Model as pure state machine with 30+ unit tests covering deuce, 30-point cap, doubles rotation for every rally, third-game side switch, undo from game-over state; separate engine from UI completely
5. **App Store rejection for subscription errors** -- Submit IAP products for review 1 week before app binary; use `SubscriptionStoreView` (handles compliance automatically); never hardcode prices; include "Restore Purchases" button; implement graceful empty state when products fail to load

## Implications for Roadmap

Based on combined research, the project divides into 4 phases with clear dependency chains.

### Phase 1: Core Scoring + Watch Companion
**Rationale:** The scoring engine is the foundation everything depends on. Watch sync is the core value proposition and the hardest reliability challenge. Ship this first to validate that people will actually score matches on their Watch.
**Delivers:** Fully functional badminton scoring app with real-time Watch companion, local match history, player profiles
**Addresses features:** BWF scoring (singles/doubles), one-tap input, undo, service tracking, Watch display/input, iPhone-Watch sync, match history, player profiles, offline operation
**Avoids pitfalls:** WatchConnectivity unreliability (#1), BWF edge cases (#5), Watch UX friction (#6), SIGKILL state loss (#7), nested TabView memory leaks (#10), audio interruption (#11)
**Critical constraint:** SwiftData models MUST use optional properties and default values from day one for future CloudKit compatibility. Retrofitting is painful and causes data migrations.

### Phase 2: Cloud, Auth, and Social Features
**Rationale:** Once scoring is validated, add persistence across devices and social stickiness. These are low-risk, well-documented Apple patterns that increase retention.
**Delivers:** Cross-device match history, user accounts, social sharing, enhanced Watch experience with HealthKit
**Addresses features:** Apple Sign-In, CloudKit sync, head-to-head records, share match results, score announcements, HealthKit workout integration, Live Activity on lock screen
**Avoids pitfalls:** CloudKit silent sync failure (#3), Apple Sign-In token expiry (#13), export edge cases (#12)
**Action item:** Deploy CloudKit schema to Production environment before any TestFlight build. Submit IAP products for review during this phase (1 week lead time before Phase 3 app binary).

### Phase 3: Hawk Eye AI + Premium Subscription
**Rationale:** The primary differentiator, but also the highest technical risk. Building on top of a product people already use for scoring de-risks the business. If accuracy is insufficient, the scoring app still has standalone value.
**Delivers:** AI-powered line-calling with visual trajectory replay, gated behind premium subscription
**Addresses features:** Camera video capture (240fps slow-motion), court calibration (manual corner marking), shuttle detection (YOLO26 nano on Core ML), trajectory prediction, visual replay with confidence indicator, subscription paywall
**Avoids pitfalls:** Unrealistic accuracy expectations (#2), battery drain (#8), court detection on non-standard surfaces (#9), App Store subscription rejection (#4)
**Gate:** Prototype shuttle detection with 50+ real court videos EARLY in this phase. If accuracy is below 70% within 10cm radius, rework the approach before building the full pipeline.

### Phase 4: Advanced Analytics and Polish
**Rationale:** Premium expansion features that increase retention and ARPU. Low risk, well-understood data aggregation patterns.
**Delivers:** Deep match analytics, data export, onboarding polish
**Addresses features:** Advanced match statistics, performance trends over time, CSV/PDF export, onboarding flow

### Phase Ordering Rationale

- Phases follow a strict dependency chain: Scoring Engine (P1) -> Cloud Sync (P2) -> Hawk Eye + Subscription (P3) -> Analytics (P4)
- Watch sync and scoring reliability must be proven before adding any complexity
- CloudKit constraints must be baked into data models from Phase 1 even though sync activates in Phase 2
- Hawk Eye is architecturally independent from scoring but depends on match context for challenge integration
- Subscription IAP products must be submitted during Phase 2 so they are approved before Phase 3 app submission
- ML model prototyping should begin early (even during Phase 1-2) as a parallel workstream to inform the Phase 3 go/no-go decision

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 1 (Watch Sync):** WatchConnectivity behavior is poorly simulated; must test on real paired devices. Research conflict resolution strategies for simultaneous scoring from both devices. BWF doubles service rotation edge cases need exhaustive test coverage.
- **Phase 3 (Hawk Eye):** Shuttle detection accuracy from single camera is unproven at consumer quality. Need prototype validation before committing to full pipeline. Research TrackNet vs YOLO26 accuracy tradeoffs for small fast-moving objects. Research 240fps slow-motion capture API availability across device models.

Phases with standard patterns (skip research-phase):
- **Phase 2 (Cloud/Auth):** CloudKit + SwiftData sync, Apple Sign-In, HealthKit, and Live Activities are well-documented with extensive Apple sample code and WWDC sessions.
- **Phase 4 (Analytics/Export):** Standard data aggregation queries and file generation. No novel technical challenges.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All Apple-native frameworks with official documentation. YOLO26 Core ML export verified via Ultralytics docs. |
| Features | HIGH | Competitive analysis of 6+ existing apps. BWF rules are deterministic. Feature gaps clearly identified. |
| Architecture | HIGH | WatchConnectivity patterns, SwiftData+CloudKit constraints, and Core ML pipelines well-documented across Apple docs and developer blogs. |
| Pitfalls | HIGH | Critical pitfalls sourced from production developer experience (fatbobman.com watchOS apps) and peer-reviewed research (PMC9655598). |

**Overall confidence:** HIGH for Phases 1-2 and 4. MEDIUM for Phase 3 -- Hawk Eye accuracy from a single consumer camera is the open question that can only be resolved through prototyping.

### Gaps to Address

- **Shuttle detection accuracy at consumer quality:** No benchmarks exist for single-camera consumer-grade detection. Professional 14-camera systems achieve 62% autonomous / 81% within 12px. Must prototype early to establish a baseline before committing resources.
- **CloudKit sync reliability on watchOS:** Multiple developer reports of unreliable SwiftData CloudKit sync to Watch. Mitigated by using WatchConnectivity exclusively, but needs real-device validation.
- **YOLO26 inference speed on older iPhones:** Benchmarked on latest devices; unclear performance on iPhone 12/13 (A14/A15 chips, which are in the iOS 17 support range). Need to test on oldest supported hardware.
- **240fps slow-motion availability:** Not all iPhones support 240fps. Need to determine minimum device requirement for Hawk Eye or gracefully degrade to 120fps.
- **Shuttle trajectory physics:** Computing landing point from partial trajectory requires physics modeling (drag, gravity, spin). Needs domain-specific research during Phase 3.
- **Subscription pricing:** Specific price point needs market validation (not a technical research question).

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation: WatchConnectivity, SwiftData, StoreKit 2, Vision, Core ML, AuthenticationServices, HealthKit
- Ultralytics YOLO26 Documentation and Core ML Export Guide
- BWF Laws of Badminton (official ruleset, Laws 6-12)
- Apple Human Interface Guidelines for watchOS

### Secondary (MEDIUM confidence)
- fatbobman.com -- Production watchOS development pitfalls from YaoYao/Tooboo apps
- PMC9655598 -- Peer-reviewed shuttlecock fall detection accuracy analysis
- Spyrosoft -- Instant Review System for Badminton (computer vision case study)
- Stanford TrackNet paper -- Shuttle trajectory tracking from monocular video
- App Store competitor analysis: Badminton Score Track Points, BadmintonPoints, ScoreKeeper, Badminton Score Tracking

### Tertiary (LOW confidence)
- Community developer reports on CloudKit + watchOS sync issues (needs validation with current iOS 18 / watchOS 11)
- Battery/thermal impact estimates for Core ML video processing (needs device-specific benchmarking)
- 240fps API availability across iPhone models (needs hardware matrix verification)

---
*Research completed: 2026-03-28*
*Ready for roadmap: yes*
