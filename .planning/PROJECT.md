# Badminton Eye

## What This Is

A native iOS app (iPhone + iPad) with Apple Watch companion for badminton players to record live match scores and view them in real-time on their wrist. Premium subscribers get access to "Hawk Eye" — an AI-powered challenge system that analyzes video footage of shuttle shots to determine whether the shuttle landed in or out of bounds.

## Core Value

Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time — making scorekeeping seamless during actual play.

## Current Milestone: v1.14 — Analytics Localization & Accessibility

**Goal:** Wire the two existing-but-unused `stats.winRate` / `stats.streak` localization keys that have been idle since v1.0, add four new format-string keys for the remaining hardcoded English in StatsView, and give VoiceOver users a meaningful experience on the Stats screen and both analytics charts.

**Target features:**
- StatsView win rate and streak labels use existing localization keys (`stats.winRate`, `stats.streak`)
- Four new format keys: `stats.winRateFormat`, `stats.streakFormat`, `stats.playMore`, `stats.matchesOf`
- StatsView empty state is fully localized across all 9 languages
- VoiceOver accessibility on StatsView summary card, WinRateTrendChart, ScoringPatternsChart

## Current State

**Shipped:** v1.9 (2026-03-30)
**Codebase:** 6,812 LOC Swift, 55 source files, 95 tests passing
**Stack:** Swift 6, SwiftUI, SwiftData + CloudKit, WatchConnectivity, Core ML, StoreKit 2, ActivityKit, HealthKit
**Dependencies:** 0 external (100% Apple-native)

## Requirements

### Validated

- ✓ Live match scoring for singles, doubles, and mixed doubles with BWF 21-point rally scoring — v1.0
- ✓ Real-time score sync between iPhone/iPad and Apple Watch (score from either device) — v1.0
- ✓ Apple Watch companion app displaying live scores, game state, and serving side — v1.0
- ✓ Match history with full score breakdowns saved to user account — v1.0
- ✓ Player profiles with win/loss records — v1.0
- ✓ Share match results via social media and messaging — v1.0
- ✓ Export match data (CSV/PDF) — v1.0
- ✓ Apple Sign-In authentication with cloud data sync — v1.0
- ✓ Premium subscription (monthly/yearly) unlocking Hawk Eye — v1.0
- ✓ Hawk Eye AI challenge system with court-side video replay and trajectory visualization — v1.0
- ✓ Live Activity on lock screen and Dynamic Island — v1.0
- ✓ iPad adaptive layout — v1.0
- ✓ HealthKit workout integration on Apple Watch — v1.0
- ✓ Match analytics with Swift Charts (win rate trends, scoring patterns) — v1.1
- ✓ Python YOLO training pipeline with CoreML export — v1.1
- ✓ 240fps delegate-based video capture with CircularFrameBuffer — v1.1
- ✓ Real CoreMLShuttleDetector via VNCoreMLRequest with frame-skip — v1.1
- ✓ BWF 3×15 scoring format with parameterized ScoringRules — v1.2
- ✓ Haptic score feedback (iPhone + Watch) with Settings toggle — v1.2
- ✓ Sequential multi-angle Hawk Eye with ResultFusionService — v1.2
- ✓ Simultaneous dual-camera capture via AVCaptureMultiCamSession — v1.3
- ✓ Audio cross-correlation for automatic multi-angle temporal alignment — v1.3
- ✓ Custom scoring format builder (user-defined points/games) — v1.3
- ✓ Custom scoring engine tests (custom rules, validation, Codable, abandon) — v1.4
- ✓ VoiceOver accessibility for LiveMatchView and ScorePanel — v1.4
- ✓ @MainActor WatchMatchViewModel with receive-side haptic feedback — v1.5
- ✓ Undo edge case tests (match-win, deuce, mid-game switch) and cross-game service tests — v1.6
- ✓ 3×15 cross-game service tests (games 2 and 3) and doubles game-3 service + boundary undo — v1.7
- ✓ Doubles deuce/cap/mid-switch tests and mixed doubles game-3 service continuity — v1.8
- ✓ 3×15 undo edge cases (deuce, mid-switch, cross-game) and mixed doubles boundary undo + mid-switch — v1.9

### Active

None (v1.5 complete)

### Out of Scope

- Android version — iOS-first, revisit after v1 validates demand
- Live streaming — not core to scoring, high complexity
- Tournament bracket management — separate domain, competitors specialize here
- Real-time multiplayer online matches — local/in-person play only
- Coaching/training features — v2+ consideration
- Multi-sport support — sport-specific focus is a strength
- Ad-supported tier — ads during play get terrible reviews

## Context

- **Platform**: Native iOS (Swift/SwiftUI) + watchOS for Apple Watch
- **AI/ML**: On-device Core ML for Hawk Eye shuttle tracking (placeholder model, needs real training data)
- **Camera**: Court-side recording (tripod recommended) at up to 240fps (v1.1)
- **Scoring rules**: BWF standard — 21 points per game, best of 3, deuce/cap, doubles service rotation
- **Target audience**: Both casual players and competitive club players
- **Data persistence**: SwiftData with CloudKit sync for cross-device access

## Constraints

- **Platform**: iOS 17+ and watchOS 10+
- **App Store**: Must comply with Apple's App Store Review Guidelines
- **Watch**: Glanceable display, minimal tap input on 45mm screen
- **Camera AI**: Placeholder model — accuracy depends on real training data, camera angle, lighting
- **Subscription**: Apple 30% cut on IAP — pricing: $4.99/mo, $29.99/yr

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Native iOS (not cross-platform) | Deep Apple Watch integration, camera APIs, and Core ML require native | ✓ Good — enabled tight Watch sync and on-device ML |
| Apple Sign-In only (no email/password) | Simplest auth for iOS-only app, Apple requires it anyway | ✓ Good — zero backend, works with CloudKit |
| Subscription model for premium | Recurring revenue supports ongoing AI model improvements | ✓ Good — $4.99/mo and $29.99/yr via StoreKit 2 |
| Court-side camera as recommended setup | Best angle for shuttle trajectory analysis | ✓ Good — 4-corner calibration adapts to angles |
| BWF scoring rules as default | Industry standard, covers 99% of play | ✓ Good — 3x15 format may need adding after April 2026 vote |
| Pure struct state machine | Zero side effects, exhaustively testable, Sendable | ✓ Good — 75 tests, shared across iOS + watchOS |
| SwiftData with CloudKit constraints from day one | Avoids painful migration when sync is enabled | ✓ Good — CloudKit worked first try |
| WatchConnectivity dual transport | applicationContext (guaranteed) + sendMessage (fast) | ✓ Good — reliable sync pattern |
| Placeholder Core ML for v1 | Ship full UX flow, train real model separately | ⚠️ Revisit — needs real data before production |

---
*Last updated: 2026-03-31 — v1.14 milestone in progress*
