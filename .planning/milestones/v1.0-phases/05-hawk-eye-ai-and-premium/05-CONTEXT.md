# Phase 5: Hawk Eye AI and Premium - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase delivers the Hawk Eye AI challenge system (court calibration, video capture, shuttle detection via Core ML, trajectory visualization with confidence indicator) and premium subscription billing via StoreKit 2. Free users retain full access to all non-premium features.

</domain>

<decisions>
## Implementation Decisions

### Hawk Eye Challenge Flow
- "Challenge" button in live match toolbar — appears after each rally, disappears after 10 seconds (time-limited like real Hawk Eye)
- Video capture: record short clip (5-10s) via in-app camera, OR select from photo library (pre-recorded tripod footage)
- Processing feedback: animated court overlay with "Analyzing..." shimmer effect + progress ring, 3-10 seconds on-device
- Result presentation: dramatic reveal — court zooms in, shuttle trajectory animates along path, landing point pulses with confidence circle — mimics TV broadcast Hawk Eye

### Court Calibration & AI Model
- Manual 4-corner tap — user taps the 4 court corners in camera view, one-time per venue, saved for reuse
- YOLO-based shuttle detector (Core ML) + physics-based trajectory extrapolation to compute landing spot. Placeholder model for v1 with documented accuracy expectations.
- Low confidence: show result with red "Low Confidence" badge — user decides whether to accept. Never force binary IN/OUT when uncertain.
- Standard 30fps for v1 (available on all iPhones). 120/240fps deferred to v2.

### Premium Subscription & Gating
- Paywall: when user taps "Challenge" button without premium — modal paywall sheet with pricing, feature preview, subscribe buttons
- Products: Monthly ($4.99) and Yearly ($29.99/year = $2.49/mo) — two simple tiers
- Free users: challenge button visible with lock icon, tapping shows paywall. All scoring, history, profiles, export remain fully free.
- Restore: "Restore Purchases" button in Settings. StoreKit 2 auto-detects across devices.

### Claude's Discretion
- Core ML model architecture details and placeholder implementation
- Court calibration corner detection UI specifics
- Trajectory animation timing and easing curves
- Paywall visual design and copy
- StoreKit 2 product identifiers

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `LiveMatchViewModel` — needs Challenge button integration and Live Activity coordination
- `MatchState` / `CodableMatchState` — match context for challenge timing
- `ScorecardRenderer` — 2D court rendering patterns reusable for trajectory overlay
- `AuthManager` — subscription status can extend auth state
- `SettingsView` — needs Restore Purchases button

### Established Patterns
- @Observable view models wrapping domain logic
- SwiftUI modal sheets for overlays
- CoreGraphics rendering (ScorecardRenderer from Phase 3)
- StoreKit 2 patterns (modern async/await API)

### Integration Points
- Challenge button added to LiveMatchView toolbar
- Camera capture uses AVFoundation (new)
- Core ML model loaded via Vision framework (new)
- Court calibration data persisted via SwiftData (new CalibrationProfile model)
- StoreKit 2 SubscriptionManager integrates with AuthManager
- Paywall sheet presented from Challenge button when not premium

</code_context>

<specifics>
## Specific Ideas

- 10-second countdown timer on Challenge button after each rally
- Court calibration: tap 4 corners, green dots confirm placement, "Recalibrate" option
- Trajectory visualization: white dotted line for flight path, colored circle for landing (green=IN, red=OUT, yellow=uncertain)
- Paywall: "Unlock Hawk Eye" header, feature preview animation, two subscription options

</specifics>

<deferred>
## Deferred Ideas

- 240fps slow-motion capture (v2 — HAWK-08)
- Multiple camera angles (v2 — HAWK-09)

</deferred>
