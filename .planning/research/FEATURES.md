# Feature Landscape

**Domain:** Badminton scoring + AI line-calling (iOS + Apple Watch)
**Researched:** 2026-03-28

## Table Stakes

Features users expect from a badminton scoring app. Missing any of these and users will leave for a competitor.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| BWF 21-point rally scoring (singles, doubles, mixed) | Every competitor has this. It is the universal ruleset. | Low | Must handle deuce (20-all, 2-pt lead) and 30-point cap. Service court alternation based on even/odd score. |
| One-tap score increment | "BadmintonPoints" and others all do this. Users expect to tap and go. | Low | Large tap targets, one hand operation. Undo last point is critical. |
| Service side / server tracking | Competitors like ScoreKeeper show visual server position. Users expect the app to know whose serve it is. | Medium | Doubles service rotation is the complex part: track which player serves and from which court (left/right based on even/odd). |
| Match history | Every established app saves past matches. Users expect to review old games. | Low | Store date, players, final scores, game-by-game breakdown. |
| Player profiles / saved players | Apps like Badminton Scorer let you save frequent opponents. Speeds up match setup. | Low | Name, optional photo, cumulative W/L record. Quick-select from list when starting a match. |
| Apple Watch score display | Multiple competitors (Badminton Score - Track Points, Badminton Score Tracking) already offer watch-only or watch-companion scoring. | Medium | Glanceable: current score, game number, server indicator. Must work with watchOS Smart Stack / Live Activities. |
| Score input from Apple Watch | Watch-only scoring apps exist (Badminton Score Tracking is watch-only). Users wearing a watch during play expect to tap scores there. | Medium | Large tap targets for each side. Haptic confirmation on point. Must work standalone (without iPhone nearby via WatchConnectivity or independent operation). |
| Real-time iPhone-Watch sync | This is the core value proposition stated in PROJECT.md. Without it, having both apps is pointless. | High | WatchConnectivity framework. Handle latency, conflict resolution if both devices score simultaneously. Bluetooth reliability during physical activity is a known challenge. |
| Undo last point | Universal in scoring apps. Mis-taps happen constantly during active play. | Low | Single undo is minimum. Multi-step undo is nice-to-have. |
| Offline operation | BadmintonPoints advertises "works offline." Players are in gyms, parks, community centers with spotty connectivity. | Low | Core scoring must work fully offline. Sync match data when connectivity returns. |

## Differentiators

Features that set Badminton Eye apart. Not expected in a scoring app, but create competitive advantage.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Hawk Eye AI challenge system (in/out determination) | **Primary differentiator.** No consumer badminton app offers this. Professional systems cost tens of thousands. Bringing even approximate line-calling to recreational play is novel. | Very High | Single-camera shuttle tracking using YOLO-based detection + trajectory prediction. Research shows 62% end-to-end accuracy with multi-camera pro setups; single-camera consumer accuracy will be lower. Must set clear user expectations with confidence indicators. See PITFALLS.md. |
| Visual trajectory replay | Showing the shuttle's predicted flight path and landing spot as an animated visualization (like TV Hawk-Eye graphics) makes the challenge feel real and exciting. | High | Render 2D court overlay with predicted landing point and confidence circle. The "TV broadcast" feel is what makes this feature magical, not just a yes/no answer. |
| Confidence indicator on challenges | Honest about AI limitations. "85% confident: IN" is more trustworthy than a false binary. | Medium | Color-coded confidence (green/yellow/red). Users understand this is recreational, not professional officiating. |
| Court calibration via camera | Let user define court boundaries in the camera feed so AI knows where lines are. One-time setup per venue. | High | Corner-point detection or manual corner marking. Perspective transform (homography) to map camera view to court coordinates. Court segmentation research shows 97.7% accuracy. |
| Apple Watch workout integration (HealthKit) | Competitors like Badminton Scoreboard already track calories and heart rate. Filling Activity Rings makes the app stickier. | Medium | Start a workout session, track active calories, heart rate, duration. Write to HealthKit. Users love seeing badminton count toward their daily goals. |
| Advanced match statistics | Win streaks, point scoring patterns, rally length trends, performance by game (do you fade in game 3?). | Medium | Computed from stored match data. Graphs and charts. Premium feature candidate. |
| Head-to-head records | "You are 7-3 against this player" with trend visualization. | Low | Query match history filtered by opponent. Simple but satisfying for competitive recreational players. |
| Score announcements (voice/haptic) | Some competitors offer spoken score announcements. Useful when you cannot look at the screen. | Low | Text-to-speech for score changes. Apple Watch haptic patterns for different events (point scored, game won). |
| Share match results | Social sharing of final scorecard as an image or link. | Low | Generate a shareable image with scores, player names, date. Share sheet integration. |
| Export match data (CSV/PDF) | For club players who track stats externally or tournament organizers who need records. | Low | CSV for data, PDF for printable scorecards. |
| Live Activity on iPhone lock screen | Show live score on lock screen without opening the app. Modern iOS feature that competitors are slow to adopt. | Medium | ActivityKit / Live Activities API. Score updates appear on Dynamic Island and lock screen. Feels premium and modern. |
| Cloud sync (cross-device) | Match history available on any device. Important when switching phones. | Medium | Apple Sign-In + CloudKit or custom backend. Match data is small, so storage costs are minimal. |

## Anti-Features

Features to explicitly NOT build. Each represents a trap that would drain resources or muddy the product.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Tournament bracket management | Separate complex domain. ScoreMine and Spogenie already specialize here. Adding brackets creates a half-baked feature competing with dedicated tools. | Integrate: let users export match results to CSV that tournament apps can import. Stay focused on individual match scoring. |
| Real-time multiplayer / online matches | Badminton is played in person. Remote scoring adds massive complexity (networking, cheating, latency) for a use case that does not exist. | Keep it local. Both players are on the same court. |
| Live streaming | High bandwidth, CDN costs, moderation concerns. Not core to scoring or line-calling. | If users want to stream, they can use the same camera feed with a separate streaming app. |
| Coaching / training drills | Different user mindset (practice vs match). Dilutes the "match scoring" identity. Feature creep into a crowded coaching app market (Birdies AI, etc.). | Consider for v2+ only if there is validated demand. |
| Automated score detection from video | Trying to use the camera to auto-detect who scored is unreliable and confusing. The camera is for Hawk Eye challenges, not continuous scoring. | Keep scoring manual (tap-based). Camera activates only for challenge replays. |
| Multi-sport support | "ScoreKeeper" tries to be everything. Spreading across sports means mediocre badminton support. | Be the best badminton scoring app. Period. Sport-specific is a strength. |
| Ad-supported free tier | Ads during active play are infuriating. They interrupt the flow of scoring. Badminton apps with ads get terrible reviews. | Use freemium: free basic scoring, premium subscription for Hawk Eye + advanced stats. No ads anywhere. |
| Custom scoring rules (non-BWF) | Edge cases (play to 11, play to 15) add UI complexity and confuse the service rotation logic. 99% of players use BWF rules. | Support BWF 21-point only. If demand emerges for 11-point format, add it as a simple toggle later. |

## Feature Dependencies

```
Court Calibration ──> Hawk Eye AI Challenge
                        │
Camera Video Capture ──>│
                        │
Shuttle Detection ─────>│──> Visual Trajectory Replay
                        │         │
                        │         v
                        └──> Confidence Indicator

Player Profiles ──> Match History ──> Head-to-Head Records
                         │
                         └──> Advanced Match Statistics

Apple Watch Score Display ──> Watch Score Input ──> iPhone-Watch Sync
                                                        │
                                                        v
                                                   Live Activity (iPhone)

BWF Scoring Engine ──> Service Side Tracking ──> Score Announcements
      │
      └──> Undo System

Apple Sign-In ──> Cloud Sync ──> Cross-Device History

HealthKit Workout ──> Apple Watch (standalone requirement)
```

## MVP Recommendation

**Phase 1 - Core Scoring (ship first, validate demand):**
1. BWF 21-point scoring (singles + doubles) with service tracking
2. One-tap scoring with undo
3. Apple Watch companion with score display and input
4. Real-time iPhone-Watch sync
5. Match history (local storage)
6. Player profiles with saved players

**Phase 2 - Polish and Stickiness:**
1. HealthKit workout integration on Watch
2. Live Activity on iPhone lock screen
3. Apple Sign-In + cloud sync
4. Head-to-head records
5. Share match results
6. Score announcements (voice/haptic)

**Phase 3 - Hawk Eye (premium feature):**
1. Camera video capture and court calibration
2. Shuttle detection AI model (on-device with Core ML)
3. Trajectory prediction and in/out determination
4. Visual trajectory replay with confidence indicator
5. Premium subscription gate

**Phase 4 - Advanced Analytics (premium expansion):**
1. Advanced match statistics and graphs
2. Export (CSV/PDF)
3. Performance trends over time

**Defer indefinitely:** Tournament brackets, live streaming, coaching, multi-sport.

**Rationale:** Ship scoring first because it validates the core user behavior (will people actually score matches on their watch?). Hawk Eye is the differentiator but is technically risky -- building it on top of a product people already use for scoring de-risks the business. If Hawk Eye accuracy proves insufficient, the scoring app still has standalone value.

## Sources

- [Badminton Score - Track Points (App Store)](https://apps.apple.com/us/app/badminton-score-track-points/id6473635854)
- [BadmintonPoints (App Store)](https://apps.apple.com/us/app/badmintonpoints/id6747377276)
- [ScoreKeeper - Match Scoring (App Store)](https://apps.apple.com/us/app/scorekeeper-match-scoring/id6749815050)
- [Badminton Score Tracking - Watch Only (App Store)](https://apps.apple.com/ng/app/badminton-score-tracking/id6756884834)
- [Spyrosoft - Instant Review System for Badminton](https://spyro-soft.com/blog/artificial-intelligence-machine-learning/instant-review-system-for-badminton-computer-vision-use-case)
- [Shuttlecock Tracking from Monocular Camera (MDPI Sensors)](https://www.mdpi.com/1424-8220/24/13/4372)
- [Automatic Shuttlecock Fall Detection - Challenges and Solutions (MDPI Sensors)](https://www.mdpi.com/1424-8220/22/21/8098)
- [Hawk-Eye Wikipedia](https://en.wikipedia.org/wiki/Hawk-Eye)
- [BWF Simplified Rules](https://system.bwfbadminton.com/documents/folder_1_81/Regulations/Simplified-Rules/Simplified%20Rules%20of%20Badminton%20-%20Dec%202015.pdf)
- [Designing for watchOS (Apple HIG)](https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos)
- [Badminton Scorer (Google Play)](https://play.google.com/store/apps/details?id=com.sportscoreboards.badmintonscorer)
- [Spogenie - Badminton Tournament Management](https://www.spogenie.com/)
- [PAiMo - Badminton Club Management](https://paimo.io/)
- [PlaySight VAR / Challenge Review System](https://playsight.com/var-video-assistant-referee/)
- [Sports App Monetization Models 2026](https://www.sportsfirst.net/post/sports-app-monetization-models-that-actually-work)
