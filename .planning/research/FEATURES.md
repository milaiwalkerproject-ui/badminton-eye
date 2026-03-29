# Feature Landscape

**Domain:** Sports AI shuttle tracking + match analytics
**Researched:** 2026-03-29

## Table Stakes

Features that must work for v1.1 to feel like a real upgrade over v1.0's placeholder.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Real shuttle detection in video | v1.0 is explicitly placeholder; users expect AI to actually work | High | Requires trained model + pipeline integration |
| Confidence-gated results | Low-confidence detections should warn user, not present false certainty | Low | Existing confidence formula + UI threshold |
| 240fps capture (with fallback) | Marketed feature; must degrade gracefully on unsupported devices | Medium | Format selection with fallback chain |
| Basic match statistics | Win/loss record, win streak, games played | Low | Computable from existing PersistedMatch data |
| Performance trend chart | Visual representation of improvement over time | Medium | Swift Charts line chart over rolling window |

## Differentiators

Features that set the app apart from basic scorekeeping competitors.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| On-device AI with no cloud dependency | Privacy-first, works offline, no latency | Already built | Core ML runs locally; this is a v1.0 differentiator maintained in v1.1 |
| 240fps shuttle tracking | Higher accuracy than any consumer badminton app | Medium | Most competitor apps do not offer frame-by-frame analysis |
| Slow-motion replay with trajectory overlay | Dramatic Hawk Eye experience | Low | TrajectoryReplayView already exists; 240fps source makes slow-mo natural |
| Scoring pattern analysis | Reveals strategic insights (when do you score/lose points?) | Medium | Requires per-game score progression extraction from stateJSON |
| Head-to-head trend analysis | Track improvement against specific opponents | Medium | Cross-references player names across matches |

## Anti-Features

Features to explicitly NOT build in v1.1.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Real-time live detection during play | Requires continuous camera feed + inference; thermal/battery issues; not the use case | Keep challenge-based model: record clip, then analyze |
| Cloud-based model inference | Adds latency, requires server, breaks offline use, privacy concern | Keep all inference on-device via Core ML |
| Automatic line calling (no user trigger) | Liability risk; too many false positives erode trust | Keep user-initiated challenge flow |
| Social/competitive leaderboards | Scope creep; requires backend infrastructure | Defer to v2+ |
| Per-rally analytics in v1.1 | Requires new SwiftData model + migration + ViewModel changes | Defer; use game-level aggregation from existing data |
| Custom model training by users | Massively complex; confusing UX | Ship one well-trained model |

## Feature Dependencies

```
240fps capture --> Higher quality input for shuttle detection
Trained YOLO model --> Real shuttle detection (replaces placeholder)
Real shuttle detection --> Confidence-gated results
ShuttleDetecting protocol --> Testability of pipeline
Existing PersistedMatch data --> Match statistics
Match statistics --> Performance trend charts
Match statistics --> Scoring pattern analysis
Swift Charts import --> All chart views
```

## MVP Recommendation

Prioritize:
1. **240fps capture with fallback** -- mechanical, testable, immediate quality improvement
2. **Core ML pipeline integration with protocol abstraction** -- enables real detection + keeps placeholder for testing
3. **Basic match statistics** (W/L, streak, games played) -- low effort, high perceived value
4. **Performance trend chart** -- one compelling visualization

Defer:
- **Scoring pattern analysis**: Medium complexity, requires deeper stateJSON parsing; ship in v1.1.1
- **Head-to-head trends**: Requires cross-match player matching; defer to v1.2
- **Per-rally analytics model**: Requires SwiftData migration; defer until rally-level data is truly needed

## Sources

- PROJECT.md active requirements (HIGH confidence)
- Existing codebase feature analysis (HIGH confidence)
- Training data knowledge of competitive badminton app landscape (LOW confidence)
