# Requirements: Badminton Eye

**Defined:** 2026-03-28
**Core Value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.

## v1 Requirements

### Scoring Engine

- [x] **SCORE-01**: User can start a new match selecting singles, doubles, or mixed doubles format
- [x] **SCORE-02**: User can tap to increment score for either side with large one-hand-friendly tap targets
- [x] **SCORE-03**: App enforces BWF 21-point rally scoring with deuce rules (2-point lead at 20-all, 30-point cap)
- [x] **SCORE-04**: App automatically tracks best-of-3 games with side switch at game end and mid-third-game
- [x] **SCORE-05**: App automatically tracks service side and server based on current score (even/odd)
- [x] **SCORE-06**: App tracks doubles service rotation (which player serves and from which court)
- [x] **SCORE-07**: User can undo the last scored point
- [x] **SCORE-08**: All scoring works fully offline without internet connectivity

### Apple Watch

- [x] **WATCH-01**: Apple Watch displays current score, game number, and server indicator in a glanceable layout
- [x] **WATCH-02**: User can tap to score from Apple Watch with large tap targets and haptic confirmation
- [x] **WATCH-03**: Score updates sync in real-time between iPhone/iPad and Apple Watch (bidirectional)
- [x] **WATCH-04**: Watch app functions independently if iPhone is temporarily unreachable
- [x] **WATCH-05**: Match automatically starts a HealthKit workout session tracking calories, heart rate, and duration
- [x] **WATCH-06**: Completed match workout data is written to HealthKit and counts toward Activity Rings

### Match Data

- [x] **DATA-01**: User can browse a list of completed matches with date, players, and final scores
- [x] **DATA-02**: User can view detailed match breakdown showing game-by-game scores
- [x] **DATA-03**: User can create and save player profiles with name and optional photo
- [x] **DATA-04**: User can quick-select saved players when starting a new match
- [x] **DATA-05**: User can view head-to-head win/loss record against a specific opponent
- [x] **DATA-06**: User can share a match result scorecard as an image via the share sheet
- [x] **DATA-07**: User can export match data as CSV or PDF

### Cloud & Authentication

- [x] **AUTH-01**: User can sign in with Apple ID (Sign in with Apple)
- [x] **AUTH-02**: Match history and player profiles sync across user's devices via CloudKit
- [x] **AUTH-03**: User can use the app without signing in (local-only mode)

### Hawk Eye AI (Premium)

- [ ] **HAWK-01**: User can initiate a Hawk Eye challenge during a match to review a disputed point
- [ ] **HAWK-02**: User can capture or select court-side video footage for the challenge
- [ ] **HAWK-03**: User can calibrate court boundaries in the camera view (one-time per venue)
- [ ] **HAWK-04**: AI analyzes shuttle trajectory from video using on-device Core ML model
- [ ] **HAWK-05**: App displays predicted landing spot on a 2D court overlay with animated trajectory visualization
- [ ] **HAWK-06**: App shows confidence indicator (percentage + color-coded) for the AI determination
- [ ] **HAWK-07**: Hawk Eye feature is gated behind premium subscription

### Premium & Billing

- [ ] **PREM-01**: User can subscribe to premium plan (monthly or yearly) via in-app purchase
- [ ] **PREM-02**: Premium subscription unlocks Hawk Eye challenges and advanced statistics
- [ ] **PREM-03**: Free users see all scoring, match history, and basic features without limitations
- [ ] **PREM-04**: Subscription status is verified via StoreKit 2 and synced across devices

### iPhone UX

- [x] **UX-01**: Active match score appears as a Live Activity on iPhone lock screen and Dynamic Island
- [x] **UX-02**: App supports both iPhone and iPad with adaptive layouts

## v2 Requirements

### Advanced Analytics

- **STATS-01**: User can view advanced match statistics (win streaks, scoring patterns, rally trends)
- **STATS-02**: User can view performance trends over time with charts and graphs
- **STATS-03**: User can see if they fade in game 3 (game-by-game performance analysis)

### UX Polish

- **VOICE-01**: App announces score changes via text-to-speech
- **HAPTIC-01**: Apple Watch provides distinct haptic patterns for different events (point, game won, match won)

### Hawk Eye Enhancements

- **HAWK-08**: Slow-motion (240fps) video capture for improved shuttle tracking accuracy
- **HAWK-09**: Multiple camera angle support for higher confidence determinations

## Out of Scope

| Feature | Reason |
|---------|--------|
| Tournament bracket management | Separate complex domain -- competitors (Spogenie, ScoreMine) specialize here |
| Real-time multiplayer / online matches | Badminton is played in person; remote scoring adds massive complexity for no use case |
| Live streaming | High bandwidth/CDN costs, not core to scoring or line-calling |
| Coaching / training drills | Different user mindset (practice vs match); dilutes product identity |
| Automated score detection from video | Unreliable; camera is for Hawk Eye challenges only, not continuous scoring |
| Multi-sport support | Sport-specific focus is a strength; spreading across sports means mediocre badminton support |
| Ad-supported tier | Ads during active play get terrible reviews; use freemium instead |
| Custom scoring rules (non-BWF) | 99% of players use BWF rules; edge cases add UI complexity for little value |
| Android version | iOS-first; revisit after v1 validates demand |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SCORE-01 | Phase 1 | Complete (01-01) |
| SCORE-02 | Phase 1 | Complete |
| SCORE-03 | Phase 1 | Complete (01-01) |
| SCORE-04 | Phase 1 | Complete (01-01) |
| SCORE-05 | Phase 1 | Complete (01-01) |
| SCORE-06 | Phase 1 | Complete (01-01) |
| SCORE-07 | Phase 1 | Complete (01-01) |
| SCORE-08 | Phase 1 | Complete |
| WATCH-01 | Phase 2 | Complete |
| WATCH-02 | Phase 2 | Complete |
| WATCH-03 | Phase 2 | Complete |
| WATCH-04 | Phase 2 | Complete |
| WATCH-05 | Phase 2 | Complete (02-03) |
| WATCH-06 | Phase 2 | Complete (02-03) |
| DATA-01 | Phase 3 | Complete (03-01) |
| DATA-02 | Phase 3 | Complete (03-01) |
| DATA-03 | Phase 3 | Complete |
| DATA-04 | Phase 3 | Complete |
| DATA-05 | Phase 3 | Complete |
| DATA-06 | Phase 3 | Complete |
| DATA-07 | Phase 3 | Complete |
| AUTH-01 | Phase 4 | Complete |
| AUTH-02 | Phase 4 | Complete |
| AUTH-03 | Phase 4 | Complete |
| HAWK-01 | Phase 5 | Pending |
| HAWK-02 | Phase 5 | Pending |
| HAWK-03 | Phase 5 | Pending |
| HAWK-04 | Phase 5 | Pending |
| HAWK-05 | Phase 5 | Pending |
| HAWK-06 | Phase 5 | Pending |
| HAWK-07 | Phase 5 | Pending |
| PREM-01 | Phase 5 | Pending |
| PREM-02 | Phase 5 | Pending |
| PREM-03 | Phase 5 | Pending |
| PREM-04 | Phase 5 | Pending |
| UX-01 | Phase 4 | Complete |
| UX-02 | Phase 2 | Complete (02-03) |

**Coverage:**
- v1 requirements: 37 total
- Mapped to phases: 37
- Unmapped: 0

---
*Requirements defined: 2026-03-28*
*Last updated: 2026-03-28 after roadmap creation*
