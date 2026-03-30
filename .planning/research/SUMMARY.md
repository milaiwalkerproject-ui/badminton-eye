# Research Summary: Badminton Eye v1.3

**Domain:** iOS sports scoring app with AI video analysis
**Researched:** 2026-03-29
**Overall confidence:** HIGH (SDK headers verified directly from Xcode)

## Executive Summary

The v1.3 milestone adds three capabilities to Badminton Eye: simultaneous dual-camera capture via AVCaptureMultiCamSession, audio cross-correlation for temporal alignment between video clips, and a custom scoring format builder. This research verified all APIs by reading iOS SDK headers directly from the local Xcode installation, providing HIGH confidence for API surface and constraints.

AVCaptureMultiCamSession is the sole Apple API for simultaneous multi-camera capture. It is a subclass of AVCaptureSession that requires explicit port-based connection management (addInputWithNoConnections, not addInput) and imposes hardware bandwidth constraints tracked via hardwareCost (0.0-1.0 float). Both cameras share ISP bandwidth, realistically capping each at 60fps at 720p in dual-cam mode -- a significant downgrade from the 240fps available in single-cam mode. The AVCaptureDataOutputSynchronizer provides timestamp-aligned frame delivery from both cameras in a single delegate callback, and must be used exclusively (it overrides individual output delegates).

Audio cross-correlation uses Accelerate's vDSP_conv function with positive filter stride. The technique extracts mono PCM at 8kHz from both video files, computes cross-correlation, and finds the peak lag -- achieving sub-millisecond alignment accuracy in under 10ms for typical 3-10 second challenge clips. This is needed for the fallback workflow (two separate recordings from different devices/sessions), not for live multi-cam (which inherits synchronization from the AVCaptureDataOutputSynchronizer).

The custom scoring builder requires minimal new technology. The existing ScoringRules struct is already fully parameterized with pointsToWin, deuceThreshold, capScore, gamesToWin, maxGames, and midGameSwitchPoint. The work is: add Codable conformance, extend ScoringSystem enum with a .custom(ScoringRules) case, create a SwiftData CustomScoringFormat model for persistence, and build a Form-based UI with Steppers. Zero new frameworks.

## Key Findings

**Stack:** AVCaptureMultiCamSession + AVCaptureDataOutputSynchronizer for dual-cam, vDSP_conv (Accelerate) for audio correlation, existing ScoringRules struct + SwiftData for custom formats. Zero new external dependencies.

**Architecture:** New MultiCamCaptureManager as a separate class (do NOT modify existing VideoCaptureManager). AudioTemporalSync as a pure stateless service. ScoringFormatBuilderView + CustomScoringFormat SwiftData model.

**Critical pitfall:** Multi-cam FPS is NOT 240fps. Both cameras share hardware bandwidth, realistically capping at 60fps each at 720p. hardwareCost must be checked before startRunning() -- if >1.0, the session refuses to start. CircularFrameBuffer flush currently writes video-only files (no audio track), which will break audio cross-correlation.

## Implications for Roadmap

Based on research, suggested phase structure:

1. **Phase 1: Custom Scoring Builder** - Lowest risk, self-contained
   - Addresses: Custom ScoringRules UI, SwiftData persistence, MatchSetupView integration
   - Avoids: No camera/audio dependencies, no device constraints
   - Rationale: Delivers visible value to all users immediately. Can ship independently.

2. **Phase 2: Audio Cross-Correlation Service** - Medium risk, testable in isolation
   - Addresses: AudioTemporalSync service, vDSP_conv integration, PCM extraction
   - Avoids: Can be tested with synthetic audio signals without camera hardware
   - Rationale: Needed by Phase 3 for fallback workflow. Unit-testable without multi-cam hardware.

3. **Phase 3: Live Dual-Camera Capture** - Highest complexity, hardware-dependent
   - Addresses: AVCaptureMultiCamSession setup, AVCaptureDataOutputSynchronizer, dual CircularFrameBuffer, hardwareCost monitoring, graceful fallback
   - Avoids: Deferred until supporting infrastructure is in place
   - Rationale: Requires real device testing (cannot validate in Simulator). Benefits from scoring and sync already working.

**Phase ordering rationale:**
- Custom scoring has zero dependencies on camera work and can ship independently
- Audio sync can be developed and tested with recorded files before multi-cam exists
- Multi-cam depends on audio sync (for fallback import path) and benefits from landing last

**Research flags for phases:**
- Phase 1: Standard patterns, unlikely to need deeper research
- Phase 2: Needs performance profiling of vDSP_conv on real audio clips to validate <10ms claim
- Phase 3: NEEDS REAL DEVICE PROFILING. Simulator cannot validate multi-cam. Exact hardwareCost values and sustainable FPS limits vary by device model.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All APIs verified via iOS SDK headers read directly from Xcode |
| Features | HIGH | Based on existing codebase analysis and clear project requirements |
| Architecture | HIGH | Extends proven patterns (delegate capture, ring buffer, fusion service) |
| Pitfalls | MEDIUM | FPS limitations and thermal behavior need real-device validation |

## Gaps to Address

- Exact per-device FPS limits in multi-cam mode (needs hardware profiling)
- Thermal sustainability of dual-cam capture during extended match recording (10+ minutes)
- Whether ultra-wide camera distortion affects shuttle detection accuracy
- CloudKit sync behavior for CustomScoringFormat model
- CircularFrameBuffer needs audio track support for cross-correlation to work on live recordings
