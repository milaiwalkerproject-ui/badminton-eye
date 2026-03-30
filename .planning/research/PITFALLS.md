# Domain Pitfalls: v1.3 Live Multi-Cam, Audio Sync & Custom Scoring

**Domain:** iOS simultaneous camera capture, audio signal processing, custom scoring
**Researched:** 2026-03-29

## Critical Pitfalls

Mistakes that cause rewrites or major issues.

### Pitfall 1: hardwareCost > 1.0 Prevents Session Start

**What goes wrong:** Configuring two cameras at formats whose combined bandwidth exceeds device capability. The session fires AVCaptureSessionRuntimeErrorNotification and refuses to start.
**Why it happens:** Developers pick the "best" format per camera (highest resolution, highest FPS) without checking combined cost. The hardwareCost property exists only on AVCaptureMultiCamSession, not standard AVCaptureSession.
**Consequences:** Black camera preview, no frames delivered, no error unless notification is observed.
**Prevention:**
1. After configuring both inputs and outputs, read `multiSession.hardwareCost` before calling `startRunning()`
2. If > 1.0: reduce FPS via `videoMinFrameDurationOverride`, try binned/cropped formats, or fall back to single-cam
3. Log hardwareCost value for diagnostics
**Detection:** Black preview. Register for AVCaptureSessionRuntimeErrorNotification.

### Pitfall 2: Using addInput Instead of addInputWithNoConnections

**What goes wrong:** Calling `multiSession.addInput()` causes auto-connection that wires both inputs to the same output. One camera appears to work, the other shows nothing or the same feed.
**Why it happens:** Developers copy existing single-cam code. Standard AVCaptureSession uses addInput/addOutput with auto-connection; AVCaptureMultiCamSession requires explicit port-based connections.
**Consequences:** Subtle bug -- both preview layers show same camera angle. Only one CircularFrameBuffer receives frames.
**Prevention:** Use ONLY addInputWithNoConnections, addOutputWithNoConnections, and explicit AVCaptureConnection(inputPorts:output:). Comment the code explaining why.
**Detection:** Both cameras show identical feed. Check frame metadata for source device type.

### Pitfall 3: No Audio Track in CircularFrameBuffer Flush

**What goes wrong:** Audio cross-correlation fails because CircularFrameBuffer.flush() writes video-only .mp4 files. There is no audio track to correlate.
**Why it happens:** The existing flush() in CircularFrameBuffer.swift (line 69-143) creates an AVAssetWriter with only a video AVAssetWriterInput. No audio input is added.
**Consequences:** AudioTemporalSync throws "no audio track" error. For live multi-cam recordings, audio sync is inherent (same timestamps), but if users export/re-import the flush files, correlation fails.
**Prevention:**
1. For live multi-cam: include AVCaptureAudioDataOutput in the synchronizer; write audio alongside video in flush
2. For imported clips: check for audio track before attempting correlation; offer manual alignment fallback
3. Always guard: `asset.loadTracks(withMediaType: .audio).first != nil`
**Detection:** AVAssetReader returns empty track list for audio. Pre-flight check before correlation.

### Pitfall 4: ScoringRules with Invalid Invariants

**What goes wrong:** User creates a custom format where capScore < pointsToWin, or gamesToWin > maxGames, producing impossible game states.
**Why it happens:** The ScoringRules struct has no validation -- it trusts the caller. If the UI allows arbitrary values without constraint enforcement, invalid rules propagate.
**Consequences:** Infinite game (score keeps going with no winner), match declared complete prematurely, or deuce logic never triggers.
**Prevention:**
1. Auto-derive deuceThreshold (= pointsToWin - 1) and maxGames (= gamesToWin * 2 - 1) -- not user-editable
2. Stepper min/max bounds enforce valid ranges
3. Add validate() method or factory on ScoringRules
4. Unit test edge cases: pointsToWin=5 (minimum), capScore=pointsToWin (no deuce), gamesToWin=1, midGameSwitchPoint=0
**Detection:** Game never reaches isGameWon, or isMatchComplete triggers after 1 game in "best of 3."

### Pitfall 5: ScoringSystem Codable Backward Incompatibility

**What goes wrong:** Adding .custom(ScoringRules) to the ScoringSystem enum changes its Codable representation. Existing persisted matches with .standard21 or .threeByFifteen fail to decode.
**Why it happens:** Swift auto-synthesized Codable for enums with associated values uses a different JSON structure than enums with raw values.
**Consequences:** App crashes on launch when loading match history. CloudKit records become undecodable.
**Prevention:**
1. Implement CUSTOM Codable conformance on ScoringSystem
2. Existing cases must decode from their v1.2 format (raw string "standard21" / "threeByFifteen")
3. New .custom case uses a different key in the JSON
4. Test decoding of v1.2 persisted data with the new enum before shipping
5. CodableMatchState already has decodeIfPresent patterns -- extend them
**Detection:** Crash on app launch with "Cannot decode ScoringSystem" error. Test with v1.2 data before release.

## Moderate Pitfalls

### Pitfall 6: Cross-Correlation Peak on Silence/Noise

**What goes wrong:** Both audio clips contain mostly silence with no distinctive transient (shuttle hit, clap). Cross-correlation returns a peak barely above noise floor, producing a meaningless offset.
**Prevention:**
1. Compute peak-to-sidelobe ratio (PSR). If peak < 2-3x mean correlation, flag as "low confidence"
2. Offer manual alignment fallback: side-by-side thumbnails where user taps the same moment
3. For live multi-cam (same device microphone), this should not occur -- ambient court sound provides signal

### Pitfall 7: Ultra-Wide Lens Barrel Distortion

**What goes wrong:** Ultra-wide camera has significant barrel distortion at edges. Shuttle detections near frame edges are geometrically displaced, causing incorrect court mapping.
**Prevention:**
1. Calibrate each camera independently -- the 4-corner calibration implicitly compensates if corners are in the distorted image space
2. Alternatively, crop ultra-wide to its undistorted center region before detection
3. Consider using only wide camera for precision detection, ultra-wide for context/confirmation

### Pitfall 8: Thermal Throttling During Extended Dual-Cam Recording

**What goes wrong:** After 5-10 minutes of dual-camera recording, device overheats. systemPressureCost exceeds 1.0, session is interrupted via AVCaptureSessionWasInterruptedNotification.
**Prevention:**
1. Monitor systemPressureCost continuously
2. At 0.8+: proactively reduce FPS on both cameras or disable secondary
3. Show user warning: "Switching to single camera to prevent overheating"
4. Consider running dual-cam only during challenge moments (last 10 seconds), not entire match

### Pitfall 9: AVCaptureDataOutputSynchronizer Overrides Individual Delegates

**What goes wrong:** Setting up the synchronizer AND calling setSampleBufferDelegate on individual outputs. From the SDK: "AVCaptureDataOutputSynchronizer overrides all the data outputs' delegates and callbacks." Individual delegates silently stop firing.
**Prevention:** Use synchronizer exclusively. Do not also set individual delegates on outputs managed by the synchronizer. This is documented in the SDK header but easy to miss.

### Pitfall 10: Dual CircularFrameBuffer Memory Pressure

**What goes wrong:** Two buffers each holding 10 seconds of 720p60 video consume significant memory (~1.5GB combined for uncompressed BGRA frames at 60fps).
**Prevention:**
1. Reduce buffer capacity for dual-cam mode: 5 seconds per buffer (still sufficient for challenge window)
2. Use binned 720p formats which reduce pixel data per frame
3. Monitor memory warnings and drop one buffer's oldest frames if needed

### Pitfall 11: Multi-Cam Format Filter Missing

**What goes wrong:** Selecting a device format that is not multi-cam compatible. From SDK: "the device's activeFormat may only be set to one of the formats for which multiCamSupported returns YES."
**Prevention:** When enumerating formats in multi-cam mode, add `format.isMultiCamSupported` filter. The existing configureHighFPSFormat() must be adapted for multi-cam with this additional constraint.
**Detection:** Session fails to start or fires runtime error. Check format.isMultiCamSupported before setting.

## Minor Pitfalls

### Pitfall 12: Stepper UX for Large Number Ranges

**What goes wrong:** Stepper with range 5-50 for pointsToWin means 45 taps to go from min to max.
**Prevention:** Use Stepper with increment of 5, or provide preset buttons (11, 15, 21, 25) alongside a Stepper for fine-tuning.

### Pitfall 13: Custom Format Name Uniqueness

**What goes wrong:** Two formats named "My Format" are indistinguishable in the picker.
**Prevention:** Enforce unique names in the save action. Show validation error on duplicates.

### Pitfall 14: vDSP_conv Stride Direction Confusion

**What goes wrong:** Passing negative stride for the filter parameter, which gives convolution instead of correlation. The peak location is mirrored.
**Prevention:** From SDK header line 2331: "this is called correlation if IF is positive and convolution if IF is negative." Always use stride +1 for cross-correlation. Add a unit test with a known signal and known offset to verify correct sign.

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Custom Scoring Builder | Invalid ScoringRules invariants (#4) | Auto-derive deuceThreshold and maxGames; validate before save |
| Custom Scoring Builder | Codable backward incompatibility (#5) | Custom Codable conformance; test with v1.2 data |
| Audio Cross-Correlation | No audio track in video (#3) | Pre-flight check; add audio to CircularFrameBuffer flush |
| Audio Cross-Correlation | Correlation on silence (#6) | Peak-to-sidelobe ratio; manual fallback |
| Audio Cross-Correlation | Stride direction confusion (#14) | Unit test with known offset |
| Dual-Camera Capture | hardwareCost > 1.0 (#1) | Check before startRunning(); iterative format reduction |
| Dual-Camera Capture | Wrong connection method (#2) | Always addWithNoConnections + explicit ports |
| Dual-Camera Capture | Thermal throttling (#8) | systemPressureCost monitoring; auto-degrade |
| Dual-Camera Capture | Synchronizer overrides delegates (#9) | Use synchronizer exclusively |
| Dual-Camera Capture | Memory pressure from two buffers (#10) | Reduce capacity to 5s in dual mode |
| Dual-Camera Capture | Non-multi-cam format selected (#11) | Filter by format.isMultiCamSupported |

## Sources

- iOS SDK headers (read directly): AVCaptureSession.h (hardwareCost, systemPressureCost documentation), AVCaptureDataOutputSynchronizer.h (delegate override warning), AVCaptureDevice.h (multiCamSupported format property), AVCaptureInput.h (videoMinFrameDurationOverride), vDSP.h (correlation vs convolution stride semantics)
- Existing codebase: CircularFrameBuffer.flush() (video-only, lines 69-143), ScoringRules struct (no validation), VideoCaptureManager (addInput pattern)
