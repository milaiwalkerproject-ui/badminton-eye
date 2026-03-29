# Roadmap: Badminton Eye

## Overview

Badminton Eye delivers a native iOS + Apple Watch badminton scoring app with an AI-powered Hawk Eye challenge system. The build progresses from a rock-solid scoring engine (the foundation everything depends on), through Watch companion and match data features, to cloud sync and authentication, and culminates with the premium Hawk Eye AI differentiator and subscription billing. Each phase delivers a complete, verifiable capability that builds on the previous.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Scoring Engine** - BWF-compliant scoring state machine with iPhone UI for singles, doubles, and mixed doubles
- [ ] **Phase 2: Apple Watch Companion** - Watch app with glanceable scores, tap-to-score, real-time sync, HealthKit workouts, and adaptive iPad layout
- [ ] **Phase 3: Match Data and Player Profiles** - Match history, player profiles, head-to-head records, sharing, and export
- [ ] **Phase 4: Cloud Sync and Authentication** - Apple Sign-In, CloudKit cross-device sync, and Live Activity on lock screen
- [ ] **Phase 5: Hawk Eye AI and Premium** - AI-powered line-calling from court-side video, visual trajectory replay, and subscription billing

## Phase Details

### Phase 1: Scoring Engine
**Goal**: Users can score a complete badminton match on iPhone with correct BWF rules, fully offline
**Depends on**: Nothing (first phase)
**Requirements**: SCORE-01, SCORE-02, SCORE-03, SCORE-04, SCORE-05, SCORE-06, SCORE-07, SCORE-08
**Success Criteria** (what must be TRUE):
  1. User can start a singles, doubles, or mixed doubles match and score points by tapping large one-hand-friendly targets
  2. App correctly enforces 21-point rally scoring with 2-point deuce lead, 30-point cap, best-of-3 games, and side switches
  3. App displays correct service side and server (including doubles rotation) after every rally
  4. User can undo the last scored point and the entire match state reverts correctly
  5. All scoring works without any internet connection
**Plans**: 3 plans

Plans:
- [x] 01-01-PLAN.md — ScoringEngine Swift package: TDD state machine with BWF rules, singles/doubles/mixed scoring, service rotation, undo
- [x] 01-02-PLAN.md — iPhone app: Xcode project, SwiftData persistence, match setup screen, live scoring UI with half-screen tap zones
- [ ] 01-03-PLAN.md — Crash recovery from SwiftData and end-to-end human verification of all scoring requirements

### Phase 2: Apple Watch Companion
**Goal**: Users can score matches from their Apple Watch with real-time sync to iPhone, plus HealthKit workout tracking
**Depends on**: Phase 1
**Requirements**: WATCH-01, WATCH-02, WATCH-03, WATCH-04, WATCH-05, WATCH-06, UX-02
**Success Criteria** (what must be TRUE):
  1. Apple Watch displays current score, game number, and server indicator in a glanceable layout with large tap targets for scoring
  2. Score changes on either device appear on the other within seconds
  3. Watch continues tracking the match independently when iPhone is temporarily out of range, and reconciles when reconnected
  4. Starting a match on Watch automatically begins a HealthKit workout; ending the match writes workout data to HealthKit and counts toward Activity Rings
  5. App adapts its layout correctly for both iPhone and iPad screen sizes
**Plans**: 3 plans

Plans:
- [x] 02-01-PLAN.md — SyncPayload type, iOS WatchSyncManager, watchOS WatchSessionManager, and WatchMatchViewModel with offline scoring
- [x] 02-02-PLAN.md — watchOS app target with Xcode project, glanceable scoring UI (top/bottom tap zones), game dots, server icon, haptics
- [x] 02-03-PLAN.md — HealthKit WorkoutManager, iPad adaptive layout with NavigationSplitView, and human verification

### Phase 3: Match Data and Player Profiles
**Goal**: Users can review match history, manage player profiles, track head-to-head records, and share or export results
**Depends on**: Phase 2
**Requirements**: DATA-01, DATA-02, DATA-03, DATA-04, DATA-05, DATA-06, DATA-07
**Success Criteria** (what must be TRUE):
  1. User can browse completed matches by date and see final scores, then drill into game-by-game breakdowns
  2. User can create player profiles with name and photo, and quickly select saved players when starting a new match
  3. User can view their win/loss record against any saved opponent
  4. User can share a match result scorecard as an image via the system share sheet
  5. User can export match data as CSV or PDF files
**Plans**: TBD

Plans:
- [ ] 03-01: SwiftData models and match history UI
- [ ] 03-02: Player profiles and head-to-head records
- [ ] 03-03: Share scorecard and CSV/PDF export

### Phase 4: Cloud Sync and Authentication
**Goal**: Users can sign in with Apple ID to sync match data across all their devices, and see live scores on their lock screen
**Depends on**: Phase 3
**Requirements**: AUTH-01, AUTH-02, AUTH-03, UX-01
**Success Criteria** (what must be TRUE):
  1. User can sign in with Apple ID and all match history and player profiles sync to their other devices via iCloud
  2. User can use the app without signing in, with all data stored locally
  3. Active match score appears as a Live Activity on iPhone lock screen and Dynamic Island
**Plans**: TBD

Plans:
- [ ] 04-01: Apple Sign-In and local-only mode
- [ ] 04-02: CloudKit sync for match data and player profiles
- [ ] 04-03: Live Activity and Dynamic Island integration

### Phase 5: Hawk Eye AI and Premium
**Goal**: Premium subscribers can challenge disputed points with AI-powered video analysis that shows where the shuttle landed
**Depends on**: Phase 4
**Requirements**: HAWK-01, HAWK-02, HAWK-03, HAWK-04, HAWK-05, HAWK-06, HAWK-07, PREM-01, PREM-02, PREM-03, PREM-04
**Success Criteria** (what must be TRUE):
  1. User can initiate a Hawk Eye challenge during a match, capture or select court-side video, and receive an AI determination
  2. User can calibrate court boundaries in the camera view (one-time per venue) for accurate coordinate mapping
  3. App displays the predicted shuttle landing spot on a 2D court overlay with animated trajectory and a color-coded confidence indicator
  4. User can subscribe to a monthly or yearly premium plan via in-app purchase; Hawk Eye is locked for free users
  5. Free users retain full access to scoring, match history, and all non-premium features without limitations
**Plans**: TBD

Plans:
- [ ] 05-01: Court calibration and video capture pipeline
- [ ] 05-02: Core ML shuttle detection and trajectory calculation
- [ ] 05-03: Visual trajectory replay and confidence rendering
- [ ] 05-04: StoreKit 2 subscription and premium feature gating

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Scoring Engine | 2/3 | In progress | - |
| 2. Apple Watch Companion | 3/3 | Complete | 2026-03-28 |
| 3. Match Data and Player Profiles | 0/3 | Not started | - |
| 4. Cloud Sync and Authentication | 0/3 | Not started | - |
| 5. Hawk Eye AI and Premium | 0/4 | Not started | - |
