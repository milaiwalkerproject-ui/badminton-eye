# Badminton Eye

## What This Is

A native iOS app (iPhone + iPad) with Apple Watch companion for badminton players to record live match scores and view them in real-time on their wrist. Premium subscribers get access to "Hawk Eye" — an AI-powered challenge system that analyzes video footage of shuttle shots to determine whether the shuttle landed in or out of bounds.

## Core Value

Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time — making scorekeeping seamless during actual play.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Live match scoring for singles, doubles, and mixed doubles with BWF 21-point rally scoring
- [ ] Real-time score sync between iPhone/iPad and Apple Watch (score from either device)
- [ ] Apple Watch companion app displaying live scores, game/set state, and serving side
- [ ] Match history with full score breakdowns saved to user account
- [ ] Player profiles with win/loss records and performance stats
- [ ] Share match results via social media and messaging
- [ ] Export match data (CSV/PDF)
- [ ] Apple Sign-In authentication with cloud data sync
- [ ] Premium subscription (monthly/yearly) unlocking Hawk Eye and advanced stats
- [ ] Hawk Eye AI challenge system: user submits court-side video replay, AI analyzes shuttle trajectory (hitting force, flight momentum, spin) to calculate landing spot and render a visual determination (in/out)
- [ ] Hawk Eye supports flexible camera angles with court-side tripod as recommended setup

### Out of Scope

- Android version — iOS-first, revisit after v1 launch
- Live streaming — not core to scoring, high complexity
- Tournament bracket management — separate domain, too complex for v1
- Real-time multiplayer online matches — local/in-person play only
- Coaching/training features — v2+ consideration

## Context

- **Platform**: Native iOS (Swift/SwiftUI) + watchOS for Apple Watch
- **AI/ML**: On-device or cloud-based computer vision for Hawk Eye shuttle tracking
- **Camera**: Court-side recording (tripod recommended) with flexible angle support; the AI adapts to different camera positions
- **Scoring rules**: BWF (Badminton World Federation) standard — 21 points per game, best of 3 games, 2-point advantage at deuce, service rotation in doubles
- **Target audience**: Both casual players (friends at parks/community centers) and competitive club players — casual-friendly UX but powerful enough for serious play
- **Data persistence**: Match data synced to user's cloud account for cross-device access and historical review

## Constraints

- **Platform**: iOS 17+ and watchOS 10+ (leveraging latest SwiftUI and HealthKit APIs)
- **App Store**: Must comply with Apple's App Store Review Guidelines, especially for subscriptions and in-app purchases
- **Watch limitations**: Apple Watch has limited screen real estate and processing — score display must be glanceable, input must be minimal taps
- **Camera AI**: Hawk Eye accuracy depends heavily on video quality, camera angle, and lighting conditions — must set clear user expectations and confidence indicators
- **Subscription**: Apple takes 30% cut on in-app subscriptions — pricing must account for this

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Native iOS (not cross-platform) | Deep Apple Watch integration, camera APIs, and Core ML require native | — Pending |
| Apple Sign-In only (no email/password) | Simplest auth for iOS-only app, Apple requires it anyway | — Pending |
| Subscription model for premium | Recurring revenue supports ongoing AI model improvements | — Pending |
| Court-side camera as recommended setup | Best angle for shuttle trajectory analysis; flexible angles supported but may reduce accuracy | — Pending |
| BWF scoring rules as default | Industry standard, covers 99% of recreational and competitive play | — Pending |

---
*Last updated: 2026-03-28 after initialization*
