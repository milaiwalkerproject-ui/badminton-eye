# Domain Pitfalls

**Domain:** iOS/watchOS badminton scoring app with AI shuttle tracking (Hawk Eye)
**Researched:** 2026-03-28

## Critical Pitfalls

Mistakes that cause rewrites, App Store rejection, or broken core functionality.

### Pitfall 1: WatchConnectivity Message Delivery Is Unreliable for Real-Time Scoring

**What goes wrong:** `sendMessage(_:replyHandler:errorHandler:)` silently fails when the Watch is not reachable (screen off, app backgrounded, Bluetooth hiccup). Score updates get lost or arrive in bulk minutes later. During a fast-paced badminton game, even a 5-second delay makes the Watch useless as a live scoreboard.

**Why it happens:** WatchConnectivity has three transport mechanisms with different reliability guarantees: `sendMessage` (real-time but requires reachability), `updateApplicationContext` (guaranteed delivery but only latest state survives), and `transferUserInfo` (queued delivery but high latency). Most developers default to `sendMessage` without fallback.

**Consequences:** Users score a point on iPhone, look at Watch, see stale score. Trust in the app collapses immediately. This is the core value proposition -- if sync is unreliable, the app is worthless.

**Prevention:**
- Use `updateApplicationContext` as the primary transport -- it guarantees the latest score state arrives even after disconnection. Score state is inherently "latest wins" (you only need current score, not history of taps).
- Use `sendMessage` as a supplementary fast path ONLY when `isReachable` is true.
- Design score state as a single serializable struct (game number, scores, server, etc.) so any single context update fully hydrates the Watch UI.
- Implement local score entry on BOTH devices independently, with conflict resolution via logical timestamps.
- Never rely on `transferUserInfo` for scoring -- its queue-based delivery adds unacceptable latency.

**Detection:** During testing, toggle Bluetooth off/on mid-match. If the Watch ever shows a stale score for more than 2 seconds after reconnection, the fallback logic is broken.

**Phase:** Phase 1 (core scoring). Must be solved before any other feature work. Test on real paired devices -- the Simulator does not accurately simulate WatchConnectivity behavior.

**Confidence:** HIGH -- multiple developer reports and Apple documentation confirm these limitations.

---

### Pitfall 2: Single-Camera Hawk Eye Accuracy Is Fundamentally Limited

**What goes wrong:** The app promises "Hawk Eye" in/out determination from a single court-side iPhone camera, but achieves unacceptably low accuracy. Users pay for a premium feature that gives wrong calls, destroying trust and generating refund requests.

**Why it happens:** Professional Hawk Eye systems use 6-14 synchronized high-speed cameras (150-200 fps) with precise 3D calibration. A single iPhone camera at 30-60 fps from one angle cannot reconstruct 3D trajectory. The shuttlecock moves at up to 400 km/h, appears as a motion-blurred streak, and is easily confused with white court lines, socks, and ad boards. Research systems using 14 cameras still only achieve 62% fully autonomous accuracy and 81% correct position detection within a 12-pixel threshold.

**Consequences:** Either the feature is inaccurate and users lose trust, or you over-invest in an impossible technical problem and never ship. This is the highest-risk feature in the entire product.

**Prevention:**
- Reframe Hawk Eye as "AI-assisted replay analysis" NOT "definitive in/out call." Show a confidence percentage and visual overlay, not a binary verdict.
- Require court calibration step: user marks the four corners of the court in the first frame. This gives you a homography matrix to map 2D image coordinates to court coordinates.
- Support only the recommended tripod setup initially. Do NOT promise "flexible camera angles" in v1 -- each angle requires different calibration and the accuracy variance is enormous.
- Use iPhone's 240fps slow-motion mode (available since iPhone 6) to capture high-speed footage, then process offline. Do NOT attempt real-time tracking.
- Build the UI to show "landing zone probability" (a heat map or ellipse) rather than a single point. This honestly communicates uncertainty.
- Set a confidence threshold below which the system says "inconclusive" rather than guessing.

**Detection:** Before building the ML pipeline, collect 50+ test videos from a single iPhone on a tripod. Manually label shuttle landing positions. If your prototype cannot achieve 70%+ agreement with manual labels within a 10cm radius, the approach needs fundamental rework.

**Phase:** Phase 3+ (premium features). Do NOT attempt this in MVP. Ship scoring first, validate product-market fit, then invest in AI.

**Confidence:** HIGH -- peer-reviewed research (PMC9655598) documents these limitations extensively.

---

### Pitfall 3: CloudKit/SwiftData Sync Fails Silently in Production

**What goes wrong:** Match history syncs perfectly in development and TestFlight, then fails completely for App Store users. Data appears to save but never syncs across devices. Users lose match history.

**Why it happens:** CloudKit requires you to manually deploy your schema to the Production environment via the CloudKit Dashboard. This is a separate step from deploying your app binary. Additionally, SwiftData+CloudKit requires ALL properties to be optional or have default values, and ALL relationships to be optional. Violating this causes silent sync failures with no error messages. Schema renames are interpreted as "delete old field + create new field," causing data loss.

**Consequences:** Users record matches, switch to a new phone, and all their history is gone. One-star reviews accumulate quickly.

**Prevention:**
- Deploy CloudKit schema to Production BEFORE submitting to App Store. Test with a production container, not just development.
- Make every SwiftData property optional or provide defaults from day one. Do not retrofit this later.
- Never rename entities or attributes after initial release. Add new fields; deprecate old ones.
- Implement a local-first architecture: all match data persists in SwiftData locally regardless of sync status. Cloud sync is a background enhancement, not a requirement.
- Add a visible sync status indicator so users know when data has synced vs. pending.

**Detection:** Test with two devices signed into the SAME iCloud account but on different networks. Create a match on device A, wait 60 seconds, check device B. If it does not appear, your production schema is not deployed.

**Phase:** Phase 2 (match history and cloud sync). Must be validated before any user-facing release.

**Confidence:** HIGH -- multiple developer blog posts document this exact failure mode, including fatbobman.com's detailed analysis.

---

### Pitfall 4: App Store Rejection for Subscription Implementation Errors

**What goes wrong:** App is rejected during review because the subscription paywall is empty (shows no products), prices are hardcoded instead of using StoreKit's `displayPrice`, or the app lacks a "Restore Purchases" button.

**Why it happens:** StoreKit 2 subscription products have a separate review cycle from the app binary. When Apple reviews your app, the subscription product may still be in "Waiting for Review" status, causing the store UI to show zero products. Additionally, Apple requires specific subscription UI elements that are easy to overlook.

**Consequences:** Weeks of delay. Each rejection-resubmission cycle takes 1-3 days. Three rejections and Apple starts scrutinizing your app more carefully.

**Prevention:**
- Submit subscription products for review BEFORE submitting the app binary. Give them at least a week lead time.
- Never hardcode prices. Always use `product.displayPrice` from StoreKit 2.
- Include a "Restore Purchases" button prominently in settings.
- Show subscription terms (price, duration, renewal policy, cancellation instructions) on the paywall screen.
- Implement a graceful empty state: if products fail to load, show a "Unable to load subscription options" message with a retry button, not a blank screen.
- Gate premium features behind entitlement checks using `Transaction.currentEntitlements`, not local flags.
- Test the entire purchase flow in Sandbox and StoreKit Testing in Xcode before submission.

**Detection:** Before submitting, verify: (1) paywall loads products in StoreKit Testing environment, (2) "Restore Purchases" button exists, (3) no hardcoded price strings anywhere in the UI, (4) subscription terms are visible.

**Phase:** Phase 3 (subscription and premium features). But submit products for review during Phase 2 so they are approved before you need them.

**Confidence:** HIGH -- well-documented by Apple and multiple developer guides.

---

### Pitfall 5: BWF Scoring Rule Edge Cases Break Match State

**What goes wrong:** Scoring logic handles the common case (rally to 21, win by 2) but fails on edge cases: deuce scenarios (20-20 requires 2-point lead, but cap at 30), service rotation in doubles (who serves, from which side), interval rules (break at 11 points), or mid-match player swaps in mixed doubles.

**Why it happens:** Developers implement the "happy path" rules and miss the combinatorial explosion of edge cases in official BWF scoring. Doubles service rotation alone involves tracking four players across two sides with rotation on service gain. The "setting" rules (deuce) interact with game-end conditions in non-obvious ways.

**Consequences:** Incorrect score state during a competitive match. Players notice immediately and lose trust. Once scoring is wrong, the entire match record is corrupted.

**Prevention:**
- Model the scoring engine as a pure state machine with exhaustive unit tests. Every state transition should be tested.
- Write tests for EVERY edge case: 20-20 deuce, 29-29 (next point wins regardless), service rotation after each rally in doubles, side-switching at 11 points in the third game, interval at 11 points in every game.
- Implement an undo stack (at least 5 levels deep) so users can correct accidental taps. The "accidental final point" problem (tapping the winning point by mistake, game ends, cannot undo) was reported in competing apps.
- Separate the scoring engine from the UI completely. The engine should be a testable Swift package with zero UI dependencies.
- Reference the official BWF Laws of Badminton document (specifically Laws 6-12) as the authoritative spec.

**Detection:** Write at least 30 unit tests covering: regular game win, deuce at 20-20, cap at 30, doubles service rotation for every rally of a full game, third game side switch, undo from game-over state.

**Phase:** Phase 1 (core scoring). This is the foundation. Get it wrong and nothing else matters.

**Confidence:** HIGH -- BWF rules are publicly documented; the edge cases are deterministic and fully testable.

---

## Moderate Pitfalls

### Pitfall 6: Apple Watch UI That Requires Too Many Taps

**What goes wrong:** The Watch scoring UI requires navigating menus, confirming dialogs, or performing multi-step interactions. During live play, the scorer has 5-10 seconds between rallies to record the point. Any friction causes them to fall behind.

**Prevention:**
- The Watch UI should be ONE TAP to record a point: tap the side that scored. No confirmation dialogs.
- Use the Digital Crown for undo (rotate back) rather than adding UI buttons.
- Display only essential info: scores, serving indicator, game number. No stats, no history, no settings on Watch.
- Use large tap targets (minimum 44pt, preferably larger) -- sweaty fingers on a small screen during exercise.
- Test with an actual player wearing the Watch during a match. If they miss taps or need to look for more than 1 second, the UI is too complex.
- Implement `isLuminanceReduced` to reduce refresh rate when the wrist is down and preserve battery.

**Phase:** Phase 1 (core scoring). The Watch UX must be designed alongside the scoring engine, not bolted on later.

**Confidence:** HIGH -- Apple's own HIG for watchOS emphasizes glanceable, minimal-tap interactions.

---

### Pitfall 7: Privacy Permission Changes Kill the Watch App Mid-Match

**What goes wrong:** If the user modifies any iPhone app privacy setting (notifications, HealthKit, location) while a match is in progress, watchOS sends SIGKILL to the Watch app. The active WatchConnectivity session is destroyed. The user sees a crash mid-match and loses unsaved score state.

**Prevention:**
- Persist score state to local storage (UserDefaults or SwiftData) after EVERY point. Never hold state only in memory.
- On Watch app launch, always check for and recover interrupted match state.
- Request all necessary permissions during onboarding, not during active gameplay.
- If the app is killed and relaunched, present a "Resume match?" prompt with the last saved state.

**Phase:** Phase 1. State persistence is a core reliability requirement.

**Confidence:** HIGH -- documented by fatbobman.com from production experience with YaoYao/Tooboo apps.

---

### Pitfall 8: Video Processing Drains Battery and Overheats the iPhone

**What goes wrong:** Users record a match (1-2 hours of video) and then run Hawk Eye analysis. The Core ML inference plus video decoding pins the CPU/GPU at 100%, the phone overheats, and battery drops 30-40% during analysis. Users blame the app.

**Prevention:**
- Process video clips, NOT full matches. Hawk Eye should analyze a 5-15 second clip of a specific rally, not hours of footage.
- Use the Neural Engine (via Core ML) instead of CPU/GPU -- it is significantly more power efficient.
- Quantize the ML model (INT8 or mixed precision) to reduce computation and memory footprint.
- Show a progress indicator with estimated time. Set expectations: "Analysis takes 10-30 seconds per clip."
- Throttle processing if thermal state is elevated: check `ProcessInfo.processInfo.thermalState` and pause/reduce quality if `.serious` or `.critical`.
- Consider cloud processing as the primary path for v1, with on-device as a future optimization. Cloud processing avoids all device thermal/battery issues.

**Phase:** Phase 3+ (Hawk Eye feature). This is a premium feature design decision that should be made early but implemented late.

**Confidence:** MEDIUM -- based on general Core ML video processing characteristics; specific benchmarks for shuttlecock models would need validation.

---

### Pitfall 9: Court Line Detection Fails on Non-Standard Courts

**What goes wrong:** The Hawk Eye court calibration assumes clean white lines on a standard court surface. In practice, recreational courts have faded lines, multi-sport line overlays (basketball, volleyball lines in the same gym), temporary tape lines on non-standard surfaces, or outdoor courts with cracks and shadows.

**Prevention:**
- Require manual court corner marking by the user rather than relying on automatic court detection. This is more reliable and handles any surface.
- Use color filtering to distinguish badminton lines (if the user identifies them) from other sport lines.
- Validate the homography: after the user marks corners, overlay a virtual court on the camera feed and ask "Does this look right?" before proceeding.
- Document supported court types. Clearly state that outdoor courts with poor line visibility may produce lower accuracy.

**Phase:** Phase 3+ (Hawk Eye). This is part of the calibration UX that must be designed carefully.

**Confidence:** MEDIUM -- based on computer vision research for badminton courts (PMC9655598) and general homography limitations.

---

### Pitfall 10: Nested TabView Memory Leaks on watchOS

**What goes wrong:** Using nested `TabView` components on watchOS causes cumulative memory growth. After several match sessions without force-quitting the app, the Watch app is terminated by the watchOS watchdog for exceeding memory limits.

**Prevention:**
- Use a flat navigation structure on Watch. One `TabView` with 2-3 pages maximum (live score, match controls).
- Never nest `TabView` inside `TabView`.
- Profile memory usage in Instruments with the Watch target over multiple simulated matches.
- Use `NavigationStack` for drill-down views rather than additional tab layers.

**Phase:** Phase 1 (Watch app architecture). Architectural decision that must be correct from the start.

**Confidence:** HIGH -- documented by fatbobman.com from production watchOS app experience.

---

## Minor Pitfalls

### Pitfall 11: Music/Audio Interruption During Scoring

**What goes wrong:** The app's audio session (haptic feedback, sound effects) interrupts the user's music playback via Bluetooth.

**Prevention:**
- Use `.ambient` audio session category, not `.playback` or `.soloAmbient`.
- Prefer haptic feedback (WKInterfaceDevice.current().play(.success)) over audio for Watch confirmations.
- Test with Bluetooth headphones playing music while scoring.

**Phase:** Phase 1. Audio session category should be set correctly from day one.

**Confidence:** MEDIUM -- reported by users of competing scoring apps.

---

### Pitfall 12: Match Export (CSV/PDF) Edge Cases

**What goes wrong:** Export generates corrupt files for matches with unusual characteristics: very long deuce games (e.g., 38-36), matches abandoned mid-game, or matches with many undo operations in history.

**Prevention:**
- Define a canonical match data model that handles all terminal and non-terminal match states.
- Test export with: completed 2-0 match, completed 2-1 match, abandoned match, match with 20+ deuce points, match with 50+ undo operations.
- Use a templating approach for PDF generation rather than manual string concatenation.

**Phase:** Phase 2 (match history features).

**Confidence:** LOW -- speculative based on general data export experience. Needs validation.

---

### Pitfall 13: Apple Sign-In Token Refresh Edge Case

**What goes wrong:** Apple Sign-In provides identity tokens that expire. If the app only validates the token at initial sign-in and never refreshes, users get silently logged out after token expiry, losing access to cloud data.

**Prevention:**
- Store the user identifier from `ASAuthorizationAppleIDCredential`, not the token itself.
- Check credential state on app launch using `ASAuthorizationAppleIDProvider.getCredentialState(forUserID:)`.
- Handle the `.revoked` state gracefully: prompt re-authentication, do not delete local data.

**Phase:** Phase 2 (authentication and cloud sync).

**Confidence:** MEDIUM -- documented in Apple's Sign In with Apple guidelines.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Phase 1: Core Scoring Engine | BWF edge cases in doubles service rotation (#5) | Pure state machine with 30+ unit tests before any UI work |
| Phase 1: Watch App | WatchConnectivity unreliability (#1), SIGKILL on permission change (#7) | applicationContext as primary transport, persist every point |
| Phase 1: Watch UI | Too many taps (#6), memory leaks (#10) | Single-tap scoring, flat navigation, no nested TabView |
| Phase 2: Cloud Sync | CloudKit schema not deployed to production (#3) | Deploy schema before first TestFlight build |
| Phase 2: Authentication | Apple Sign-In token expiry (#13) | Store user ID, check credential state on launch |
| Phase 3: Subscriptions | Empty product list during review (#4) | Submit IAP products 1 week before app binary |
| Phase 3+: Hawk Eye | Accuracy expectations (#2), battery drain (#8), court detection (#9) | Reframe as "AI-assisted," use clips not full video, manual court calibration |

## Sources

- [watchOS Development Pitfalls and Practical Tips - fatbobman.com](https://fatbobman.com/en/posts/watchos-development-pitfalls-and-practical-tips)
- [WatchConnectivity Data Synchronization - Medium](https://medium.com/@sheik25bareeth/data-synchronization-between-ios-and-watchos-using-watchconnectivity-009a3064e12a)
- [First App Journey: WatchConnectivity Lessons - DEV Community](https://dev.to/cloutboi/first-app-journey-learned-the-hard-way-about-watchconnectivity-2d4b)
- [Instant Review System for Badminton - Spyrosoft](https://spyro-soft.com/blog/artificial-intelligence-machine-learning/instant-review-system-for-badminton-computer-vision-use-case)
- [Automatic Shuttlecock Fall Detection - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC9655598/)
- [Fixing SwiftData & CloudKit Sync - fatbobman.com](https://fatbobman.com/en/snippet/resolving-incomplete-icloud-data-sync-in-ios-development-using-initializecloudkitschema/)
- [Rules for Adapting Data Models to CloudKit - fatbobman.com](https://fatbobman.com/en/snippet/rules-for-adapting-data-models-to-cloudkit/)
- [App Store Review Guidelines Checklist - nextnative.dev](https://nextnative.dev/blog/app-store-review-guidelines)
- [StoreKit 2 Guide - Medium](https://medium.com/@dhruvinbhalodiya752/mastering-storekit-2-in-swiftui-a-complete-guide-to-in-app-purchases-2025-ef9241fced46)
- [Watch Connectivity - Apple Developer Documentation](https://developer.apple.com/documentation/watchconnectivity)
- [Core ML Overview - Apple Developer](https://developer.apple.com/machine-learning/core-ml/)
