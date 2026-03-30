---
phase: 08-240fps-video-capture
plan: 02
subsystem: video-capture-ui
tags: [challenge-ui, fps-badge, slow-motion, buffer-capture, avplayer]
dependency_graph:
  requires: [CircularFrameBuffer, delegate-based-capture, high-fps-format-selection]
  provides: [buffer-based-challenge-capture, fps-fallback-banner, slow-motion-replay]
  affects: [ChallengeVideoView, TrajectoryReplayView]
tech_stack:
  added: [AVKit-VideoPlayer]
  patterns: [buffer-flush-capture, fps-aware-playback-rate, conditional-ui-by-capability]
key_files:
  created: []
  modified:
    - BadmintonEye/BadmintonEye/Views/ChallengeVideoView.swift
    - BadmintonEye/BadmintonEye/Views/TrajectoryReplayView.swift
decisions:
  - Buffer capture replaces start/stop recording paradigm (continuous circular buffer with flush-to-disk)
  - FPS badge color thresholds at 240/120/60/30 (green/yellow/orange/red)
  - Slow-mo toggle hidden for captureFPS < 120 (no slow-mo for 30fps footage per user decision)
  - Playback rate formula 30.0/captureFPS gives 8x slower for 240fps and 4x slower for 120fps
  - Default captureFPS=30 for backward compatibility with library-selected videos
metrics:
  completed: 2026-03-30
  tasks_completed: 3
  tasks_total: 3
---

# Phase 8 Plan 02: Challenge Capture UI and Slow-Motion Replay Summary

Buffer-based challenge capture with FPS badge, 30fps fallback banner, and slow-motion replay toggle for 240fps/120fps footage in TrajectoryReplayView.

## What Was Done

### Task 1: Update ChallengeVideoView for buffer capture and FPS fallback

Replaced the old start/stop recording toggle with continuous circular buffer capture. On view appear, `startRecording()` begins capturing into the circular buffer immediately. The record button was replaced with a "Save Last 10s" button that calls `saveBufferToDisk()` to flush the buffer to disk.

Added FPS badge overlay at top-right of camera preview showing current capture rate with color-coded indicator (green >= 240, yellow >= 120, orange >= 60, red for 30fps).

Added fallback banner for 30fps devices: "Recording at 30fps -- For best results, use iPhone 12 or newer." Banner only appears when `currentFPS <= 30` and `currentFPS > 0`.

Updated buffer duration display to show "Buffer: Xs / 10.0s" instead of plain duration counter. Progress bar tint changed from red to yellow to match challenge theme.

Back button now calls both `stopRecording()` and `cleanup()` to properly tear down session and clear buffer.

Updated fullScreenCover call site to pass `videoURL` and `captureFPS` to TrajectoryReplayView.

### Task 2: Add slow-motion replay toggle to TrajectoryReplayView

Added `import AVKit` and new parameters: `videoURL: URL?` (default nil) and `captureFPS: Double` (default 30) for backward compatibility.

Added VideoPlayer section above the court diagram that shows when videoURL is non-nil. Below the video player, a slow-motion toggle button appears only when `captureFPS >= 120`.

Slow-motion playback rate: `30.0 / captureFPS` -- for 240fps this gives 0.125 (8x slower), for 120fps gives 0.25 (4x slower). Toggle switches between slow-mo and normal speed by setting `player.rate`.

Toggle shows tortoise icon for slow-mo mode, hare icon for normal speed. Button background changes to blue when slow-mo is active.

Player initializes and auto-plays on appear if videoURL is provided.

### Task 3: Checkpoint verification (auto-approved)

Auto-approved per YOLO mode. Full capture-to-replay flow: FPS badge, fallback banner, buffer save, video replay with slow-mo toggle.

## Deviations from Plan

None -- plan executed exactly as written.

## Verification Results

- `saveBufferToDisk` present in ChallengeVideoView.swift: PASS
- `currentFPS` present in ChallengeVideoView.swift: PASS (3 occurrences)
- `30fps` fallback banner present: PASS
- `For best results` text present: PASS
- `isSlowMotion` present in TrajectoryReplayView.swift: PASS (5 occurrences)
- `captureFPS` present in TrajectoryReplayView.swift: PASS (4 occurrences)
- `AVPlayer` present in TrajectoryReplayView.swift: PASS
- `rate` present in TrajectoryReplayView.swift: PASS
- `captureFPS` passed from ChallengeVideoView: PASS
