# Domain Pitfalls: v1.3 Simultaneous Dual-Camera, Audio Cross-Correlation Sync, Custom Scoring Formats

**Domain:** Adding simultaneous multi-cam capture, audio-based temporal alignment, and user-defined scoring to existing iOS badminton scoring app
**Researched:** 2026-03-29
**Overall confidence:** MEDIUM (no web search available; based on codebase analysis + training data knowledge of Apple AVFoundation, Accelerate, SwiftData/CloudKit APIs)

---

## Area 1: AVCaptureMultiCamSession -- Simultaneous Dual-Camera Capture

### Critical Pitfall 1.1: A12+ Chip Requirement Silently Excludes Users

**Risk Level:** CRITICAL
**What goes wrong:** `AVCaptureMultiCamSession.isMultiCamSupported` returns `false` on any device with a chip older than A12 (iPhone X and earlier). But the subtler problem is that even on A12+ devices, specific camera *combinations* may not be supported. For example, running back wide-angle + back ultra-wide simultaneously requires A13+ on some models. The developer checks `isMultiCamSupported` (true on iPhone XS) and assumes all camera pairs work, then discovers at runtime that the specific input set they need is rejected by `canAddInput`.
**Why it happens in this codebase:** `VideoCaptureManager` currently grabs `.builtInWideAngleCamera` for `.back` position. For dual-cam, the natural second camera is `.builtInUltraWideCamera` or the front-facing camera. The set of allowed simultaneous input combinations is device-specific and NOT queryable via a single API -- you must call `AVCaptureDevice.DiscoverySession` and then test each pairing.
**Consequences:** Feature appears available (isMultiCamSupported is true) but crashes or fails when the specific camera pair is added to the session. Users on supported devices get inconsistent behavior.
**Prevention:**
- After checking `isMultiCamSupported`, also call `AVCaptureMultiCamSession().canAddInput()` for each proposed input BEFORE committing to multi-cam mode
- Build a `MultiCamCapabilityChecker` that probes available camera pairs at app launch and caches results
- Show specific UI: "Dual wide+ultra-wide available" or "Front+back available" -- not just "Multi-cam supported"
- Test on physical devices: iPhone XS (A12, 4GB), iPhone 11 (A13, 4GB), iPhone 13 Pro (A15, 6GB), iPhone 15 Pro (A17, 8GB)
**Detection:** Feature works in simulator but fails on physical device. Or works on iPhone 15 Pro but not iPhone XS.

### Critical Pitfall 1.2: FPS Limits Per Camera in MultiCam Mode

**Risk Level:** CRITICAL
**What goes wrong:** `AVCaptureMultiCamSession` imposes per-camera FPS limits that are LOWER than single-camera maximums. A device that supports 240fps in single-cam mode may only allow 120fps or 60fps per camera in multi-cam mode. The system balances ISP bandwidth across cameras. The existing `configureHighFPSFormat(for:)` in `VideoCaptureManager` selects the highest available FPS -- but this format may be rejected or silently downgraded when used inside a multi-cam session.
**Why it happens in this codebase:** `configureHighFPSFormat` iterates `device.formats` and picks the highest FPS at 720p. In multi-cam mode, the available formats are the same, but setting `activeVideoMinFrameDuration` to 1/240 on BOTH cameras simultaneously causes the session to refuse to start, or causes one camera to silently drop frames.
**Consequences:** Primary camera drops from 240fps to 120fps or 60fps without the code knowing. `CircularFrameBuffer` eviction timing is based on presentation timestamps, not frame count, so the buffer still works -- but shuttle detection quality degrades because fewer frames are captured. The "upgrade" to multi-cam actually makes single-camera detection worse.
**Prevention:**
- Query `AVCaptureDevice.Format.supportedMultiCamVideoFormats` (available on each format) to find formats explicitly allowed in multi-cam mode
- Use `device.activeFormat.videoSupportedFrameRateRanges` AFTER setting up the multi-cam session to see actual available FPS
- Design asymmetric FPS from the start: primary camera at the highest multi-cam-allowed FPS (e.g., 120fps), secondary at 60fps or 30fps
- Do NOT assume 240fps is available in multi-cam mode on any device
- Log actual achieved FPS to analytics so you can verify real-world behavior
**Detection:** `currentFPS` shows 240 (what was requested) but actual frame delivery rate is lower. Add a frame-rate counter that measures actual `captureOutput` callback frequency.

### Critical Pitfall 1.3: Thermal Throttling Kills Multi-Cam Before Single-Cam

**Risk Level:** CRITICAL
**What goes wrong:** Running two cameras simultaneously generates significantly more heat than one. The ISP, neural engine (if doing on-device detection), and display all compete for thermal budget. iOS thermal management will throttle camera FPS, reduce resolution, or interrupt the capture session entirely via `AVCaptureSession.InterruptionReason.videoDeviceNotAvailableDueToSystemPressure`. This happens within 2-5 minutes of continuous dual-cam capture in warm environments (outdoor badminton courts).
**Why it happens in this codebase:** The existing `VideoCaptureManager` has no thermal monitoring. `startRecording()` fires and forgets. The 10-second `CircularFrameBuffer` window means the system runs continuously for the entire match duration (potentially 30-60 minutes), not just during challenges.
**Consequences:** Camera session is interrupted mid-match. User tries to trigger a Hawk Eye challenge and gets no footage because the capture silently stopped. Worst case: both cameras throttle, primary loses frames at the critical moment.
**Prevention:**
- Register for `ProcessInfo.processInfo.thermalState` notifications (`.nominal`, `.fair`, `.serious`, `.critical`)
- At `.serious`: drop secondary camera to 30fps or pause it entirely; keep primary at highest available FPS
- At `.critical`: drop to single-camera mode and notify the user
- Do NOT run both cameras continuously for the entire match. Run primary continuously, start secondary only when a potential challenge situation is detected (shuttle near boundary) or when the user pre-arms a challenge
- Alternatively: run secondary camera in low-power mode (720p @ 30fps) for "angle validation" only, not for high-FPS trajectory analysis
- Profile thermal behavior on iPhone XS (smallest battery, worst thermal dissipation in the multi-cam-capable lineup)
**Detection:** Test by running the app for 10+ minutes in a warm room. Monitor thermal state in Instruments. If `thermalState` reaches `.serious` within 5 minutes, the continuous dual-cam strategy is not viable.

### Critical Pitfall 1.4: Dual CircularFrameBuffer Memory Pressure (~4-8GB)

**Risk Level:** CRITICAL
**What goes wrong:** The existing `CircularFrameBuffer` retains `CMSampleBuffer` references in a Swift array. Each 720p YCbCr buffer is ~1.8MB. At 240fps for 10 seconds, that is 2,400 buffers = ~4.3GB for ONE camera. Two cameras at 240fps = ~8.6GB. Even iPhone 15 Pro (8GB total RAM) cannot sustain this -- the OS Jetsam threshold for apps is typically 2-4GB depending on device.
**Why it happens in this codebase:** `CircularFrameBuffer` stores `[CMSampleBuffer]` and evicts by timestamp. The array grows unbounded within the capacity window. There is no memory ceiling, no monitoring of `os_proc_available_memory()`, and no back-pressure mechanism to drop frames when memory is tight.
**Consequences:** App killed by Jetsam (OOM) during multi-cam capture. All buffered footage lost. No crash log visible to user -- app just disappears.
**Prevention:**
- MUST use asymmetric FPS: primary at 120fps (multi-cam limit on most devices), secondary at 30-60fps
- MUST reduce buffer capacity per camera: primary 8 seconds, secondary 5 seconds
- At 120fps x 8s = 960 buffers x 1.8MB = ~1.7GB (primary); 60fps x 5s = 300 buffers x 1.8MB = ~540MB (secondary). Total ~2.2GB -- tight but viable
- Better approach: write secondary camera frames directly to a rolling `AVAssetWriter` on disk instead of buffering in memory. Disk I/O is fast enough at 60fps 720p.
- Add a memory pressure observer: `DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical])` and shed secondary buffer on warning
- Add a `maxBufferCount` property to `CircularFrameBuffer` as a hard ceiling in addition to time-based eviction
**Detection:** Profile in Instruments Memory graph. If resident memory exceeds 2.5GB, the strategy must change.

### Moderate Pitfall 1.5: Existing VideoCaptureManager Is Not Multi-Cam-Aware

**Risk Level:** MODERATE
**What goes wrong:** `VideoCaptureManager` creates an `AVCaptureSession` (single-cam). Upgrading to `AVCaptureMultiCamSession` is NOT a drop-in replacement. Multi-cam sessions require different input/output wiring: each camera gets its own `AVCaptureDeviceInput` and `AVCaptureVideoDataOutput`, connected via specific `AVCaptureConnection` objects. The existing code adds one input and one output to one session.
**Why it happens in this codebase:** `VideoCaptureManager` was correctly designed for single-camera. It stores one `captureSession`, one `videoDataOutput`, one `circularBuffer`. The entire class assumes a single camera.
**Consequences:** Attempting to retrofit multi-cam into the existing class creates a tangled mess of optional second cameras, conditional logic, and two code paths in every method.
**Prevention:**
- Do NOT modify `VideoCaptureManager`. Keep it as the single-camera implementation.
- Create a new `MultiCamCaptureManager` that creates an `AVCaptureMultiCamSession` and manages two separate `AVCaptureVideoDataOutput` instances, each with its own `CircularFrameBuffer`
- Use a protocol `CaptureManaging` that both classes conform to, with the common interface (`startRecording`, `stopRecording`, `saveBufferToDisk`)
- `HawkEyePipeline` receives footage from whichever manager is active
- Feature detection at startup determines which manager to instantiate
**Detection:** Code review: if `VideoCaptureManager` starts accumulating `if isMultiCam` branches, refactor to separate class.

### Moderate Pitfall 1.6: AVCaptureDataOutputSynchronizer Latency vs Independent Delegates

**Risk Level:** MODERATE
**What goes wrong:** `AVCaptureDataOutputSynchronizer` delivers synchronized frame groups from multiple cameras, but introduces latency -- it must wait for the slowest camera's frame before delivering the group. If primary runs at 120fps and secondary at 60fps, the synchronizer delivers at 60fps (the slower rate), effectively halving primary camera frame throughput. Alternatively, it can deliver unmatched frames, but the API for handling partial groups is more complex.
**Why it happens:** The synchronizer guarantees temporal alignment but at the cost of throughput parity. With asymmetric FPS, the mismatch is significant.
**Consequences:** Using the synchronizer defeats the purpose of high-FPS primary capture. Not using it means frames are unsynchronized and cross-correlation in the Hawk Eye pipeline must handle temporal misalignment.
**Prevention:**
- For v1.3 with audio cross-correlation sync, frame-level synchronization between cameras is LESS critical because audio alignment handles temporal sync in post-processing
- Use independent delegates (no synchronizer) for capture, storing frames in separate buffers
- Use audio cross-correlation (see Area 2) to align the two video streams temporally during analysis
- This decouples capture from analysis and preserves full primary FPS
**Detection:** If using synchronizer and primary FPS drops to match secondary, switch to independent delegates.

---

## Area 2: Audio Cross-Correlation for Temporal Alignment

### Critical Pitfall 2.1: Audio Input Not Captured by Default in VideoCaptureManager

**Risk Level:** CRITICAL
**What goes wrong:** The existing `VideoCaptureManager` creates only `AVCaptureVideoDataOutput`. It does NOT add `AVCaptureAudioDataOutput`. Without audio buffers in the circular buffer, there is no audio track to use for cross-correlation. The developer must add audio capture to the pipeline, which means modifying `CircularFrameBuffer` to store both video and audio sample buffers, or using a separate audio buffer.
**Why it happens in this codebase:** `CircularFrameBuffer` is typed for `CMSampleBuffer` but treats all buffers as video (the `flush` method only writes to a video `AVAssetWriter` input). Audio `CMSampleBuffer` objects would need a separate `AVAssetWriterInput` for the audio track.
**Consequences:** Without audio capture, cross-correlation is impossible. Retrofitting audio into the existing buffer system is invasive.
**Prevention:**
- Add `AVCaptureAudioDataOutput` to both single-cam and multi-cam sessions
- Store audio buffers in a SEPARATE lightweight ring buffer (audio is tiny compared to video -- 48kHz stereo PCM is ~384KB/sec vs ~430MB/sec for 240fps 720p video)
- When flushing to disk, write both video and audio tracks to the .mp4 via separate `AVAssetWriterInput` instances
- Alternatively, capture audio into a separate raw PCM buffer specifically for cross-correlation, without embedding it in the video file
- Audio needs to share the same timestamp domain as video (both use `CMSampleBuffer` presentation timestamps from the same clock, so this is automatic)
**Detection:** Play back a captured .mp4 -- if there is no audio track, cross-correlation will fail.

### Critical Pitfall 2.2: vDSP Cross-Correlation Precision With Short Audio Windows

**Risk Level:** CRITICAL
**What goes wrong:** Audio cross-correlation finds the time offset between two recordings by computing the cross-correlation function. Using Accelerate `vDSP_conv` or FFT-based correlation (`vDSP_fft_zop` + multiply + inverse FFT`), the result is a lag value in samples. At 48kHz, each sample is ~20.8 microseconds. For a shuttle moving at 400km/h (111 m/s), 1ms of alignment error = 11cm of position error. The cross-correlation peak must be resolved to sub-sample precision to achieve useful alignment.
**Why it happens:** Naive cross-correlation finds the integer sample offset with the highest correlation value. But the true peak often lies between samples. Without sub-sample interpolation (parabolic or sinc interpolation around the peak), alignment accuracy is limited to +/- 0.5 samples (~10 microseconds at 48kHz), which translates to ~1.1mm of shuttle position error -- actually acceptable. The REAL problem is when the audio signals are too different (different microphone positions, different room acoustics, different SNR) and the correlation peak is ambiguous or noisy.
**Consequences:** If the correlation peak is ambiguous (multiple peaks of similar height due to reverberant gymnasium acoustics), the algorithm picks the wrong offset and the two camera streams are aligned to the wrong moment. The fused Hawk Eye result is worse than single-camera.
**Prevention:**
- Use a specific impulsive sound event for correlation: the shuttle hitting the racket or the floor produces a sharp acoustic transient that cuts through reverb
- Bandpass filter audio to 2-8kHz before correlation (shuttle impact frequency range) to suppress low-frequency gym noise and high-frequency hiss
- Use `vDSP.correlate(_:withKernel:)` (Swift overlay) for the correlation, then parabolic interpolation on the peak for sub-sample accuracy
- Validate the correlation peak: if `peakValue / rms(correlationSignal) < threshold`, the alignment is unreliable -- fall back to timestamp-based alignment (which is accurate to ~2-4ms from hardware clock sync)
- Set a maximum expected offset window (e.g., +/- 100ms). If the peak falls outside this window, the audio is from different events -- reject it
**Detection:** Log the correlation peak SNR (peak-to-second-peak ratio). If < 3:1, alignment quality is poor.

### Critical Pitfall 2.3: FFT Length and Performance for Real-Time Correlation

**Risk Level:** HIGH
**What goes wrong:** FFT-based cross-correlation requires FFT length >= len(signal1) + len(signal2) - 1, rounded up to a power of 2. For 10 seconds of 48kHz mono audio, each signal is 480,000 samples. The FFT must be at least 1,048,576 points (2^20). `vDSP_fft_zop` handles this efficiently (Accelerate is SIMD-optimized), but the developer must correctly:
1. Zero-pad both signals to the same power-of-2 length
2. Use `vDSP_DFT_zop_CreateSetup` (or `vDSP_fft_zop`) for forward FFT
3. Multiply the spectra (one conjugated) element-wise
4. Inverse FFT
5. Find the peak in the result

Each step has precision and memory allocation pitfalls. Using `Float` (single precision) is fine for audio correlation, but accidentally using `Double` throughout doubles memory usage for no benefit.
**Why it happens:** Developers unfamiliar with vDSP use the wrong function variants, forget zero-padding, or allocate temporary buffers incorrectly.
**Consequences:** Incorrect correlation result (wrong offset), excessive memory allocation, or slow performance.
**Prevention:**
- Use the modern Swift Accelerate overlay: `vDSP.correlate(_:withKernel:)` handles the FFT internally for shorter signals, but for 480K-sample signals, you need explicit FFT-based correlation
- Use `Float` (single precision) throughout -- `vDSP` functions are `Float`-native and NEON-optimized
- Pre-allocate FFT setup with `vDSP_DFT_zop_CreateSetup` once and reuse across correlations
- Total memory for FFT-based correlation of two 10-second clips: ~4 * 1M * 4 bytes = ~16MB -- negligible
- Benchmark: on A12+, a 1M-point FFT completes in <10ms. The full cross-correlation pipeline (two FFTs + multiply + one IFFT + peak find) should complete in <50ms
- Do NOT use time-domain convolution (`vDSP_conv`) for signals this long -- O(n^2) vs O(n log n) for FFT
**Detection:** Measure wall-clock time for the correlation step. If >200ms, something is wrong (likely using time-domain convolution or Double precision).

### Moderate Pitfall 2.4: Microphone Access Permission and Multi-Cam Audio

**Risk Level:** MODERATE
**What goes wrong:** Adding audio capture requires `NSMicrophoneUsageDescription` in Info.plist and user permission. The app already has camera permission but may not have microphone permission. In an `AVCaptureMultiCamSession`, adding an `AVCaptureAudioDataOutput` routes audio from the DEVICE microphone, not from a specific camera. Both "cameras" share the same microphone. This means cross-correlation between the two camera streams' audio tracks is identical -- there is no offset to find.
**Why it happens:** Cross-correlation alignment assumes two DIFFERENT devices (two iPhones) recording from different positions. If both camera streams come from one device (front + back camera on the same iPhone), their audio is from the same microphone and cross-correlation yields zero offset.
**Consequences:** The feature is useless for single-device multi-cam. Cross-correlation only makes sense when aligning footage from two SEPARATE iPhones placed at different court positions.
**Prevention:**
- Clarify the use case: Audio cross-correlation is for aligning video from TWO SEPARATE DEVICES, not for two cameras on one device
- For single-device multi-cam (front+back on one iPhone): use the shared hardware clock -- both camera streams already share `CMSampleBuffer` timestamps from the same clock, so alignment is trivial (zero offset)
- For two-device alignment: each device records video+audio independently, then the user imports both clips and the app computes the audio cross-correlation to find the temporal offset
- Update the UI flow: "Import second angle from another iPhone" triggers audio-based alignment; "Use front+back cameras" uses hardware clock alignment (no audio needed)
**Detection:** If cross-correlation is yielding zero offset on every test, the audio is from the same mic.

### Moderate Pitfall 2.5: Audio Drift Between Two Separate Devices Over Time

**Risk Level:** MODERATE
**What goes wrong:** Two iPhones recording independently use different crystal oscillators for their audio sample clocks. These clocks drift relative to each other at ~20-50 ppm (parts per million), meaning over a 10-second clip, the audio can drift by 200-500 microseconds (0.2-0.5ms). Over longer recordings, drift accumulates linearly.
**Why it happens:** Consumer device clocks are not synchronized. NTP accuracy on WiFi is ~10-50ms, useless for frame-level alignment. Bluetooth PTP (Precision Time Protocol) is not available on iOS.
**Consequences:** Cross-correlation finds the correct offset at the START of the clip, but by the end of a 10-second clip, the alignment is off by up to 0.5ms -- acceptable for shuttle tracking (0.5ms at 111m/s = 5.5cm). But if users record longer clips or the buffer window increases, drift becomes significant.
**Prevention:**
- The 10-second CircularFrameBuffer window keeps drift bounded to <0.5ms -- acceptable
- If longer recordings are needed later, implement windowed cross-correlation: correlate in 1-second chunks and compute a per-chunk offset, then linearly interpolate
- Do NOT assume a single global offset for recordings longer than 10 seconds
- For v1.3 with 10-second buffers, this is a non-issue. Flag for future if buffer duration increases.
**Detection:** If trajectory fusion shows increasing disagreement between cameras toward the end of the clip, drift is the likely cause.

---

## Area 3: Custom Scoring Format Builder

### Critical Pitfall 3.1: ScoringRules Has Fixed Fields -- User-Defined Rules Need Validation

**Risk Level:** CRITICAL
**What goes wrong:** `ScoringRules` is a struct with six fixed `let` fields: `pointsToWin`, `deuceThreshold`, `capScore`, `gamesToWin`, `maxGames`, `midGameSwitchPoint`. The `ScoringSystem` enum maps to one of two static instances (`.standard21`, `.threeByFifteen`). Adding user-defined custom rules means creating `ScoringRules` with arbitrary values. The scoring engine (BWFRules.swift, MatchEngine.swift) assumes these values are internally consistent (e.g., `deuceThreshold < capScore`, `gamesToWin <= maxGames`, `midGameSwitchPoint < pointsToWin`). User input can violate these invariants.
**Why it happens in this codebase:** The two existing `ScoringRules` instances are hardcoded and correct by construction. There is no validation because the values were never user-provided. The struct has no `init` validation -- it is a plain struct with `let` fields initialized via memberwise init.
**Consequences:** A user sets `pointsToWin: 5, deuceThreshold: 10` (threshold > target). `isDeuce` returns `false` always (scores never reach 10), and the game ends at 5-0 with no deuce possible -- this is actually fine and probably what the user wanted. But `capScore: 3` with `pointsToWin: 5` means the game caps at 3, which is before `pointsToWin` -- the game can never be won normally. `maxGames: 0` causes array index out of bounds. `midGameSwitchPoint: 0` triggers side switch on every point.
**Prevention:**
- Add a validated initializer to `ScoringRules`: `init?(pointsToWin:deuceThreshold:capScore:gamesToWin:maxGames:midGameSwitchPoint:)` that returns `nil` for invalid combinations
- Validation rules:
  - `pointsToWin >= 1`
  - `deuceThreshold >= pointsToWin - 1` (deuce activates at 1 below win target, or set equal to pointsToWin to disable deuce)
  - `capScore >= pointsToWin` (cap cannot be below win target)
  - `gamesToWin >= 1`
  - `maxGames >= gamesToWin * 2 - 1` (must be possible for both sides to reach gamesToWin - 1 wins)
  - `midGameSwitchPoint >= 1 && midGameSwitchPoint <= pointsToWin`
- The existing `static let standard21` and `static let threeByFifteen` bypass validation (known-good)
- The UI builder should constrain inputs so invalid combinations are impossible (e.g., slider ranges, dependent pickers)
**Detection:** Any test where custom rules cause an infinite loop in MatchEngine (game never ends) or array out of bounds.

### Critical Pitfall 3.2: ScoringSystem Enum Cannot Represent Custom Rules

**Risk Level:** CRITICAL
**What goes wrong:** `ScoringSystem` is currently an enum with two cases: `.standard21` and `.threeByFifteen`. Adding custom scoring means either:
- (A) Adding a `.custom` case with associated values -- but `ScoringSystem` is `Codable` with `String` raw values, and associated values break `RawRepresentable`
- (B) Adding a `.custom(id: UUID)` case -- breaks raw value conformance
- (C) Keeping the enum and storing custom rules separately -- but then `ScoringRules.rules(for:)` cannot resolve custom systems without access to a database

**Why it happens in this codebase:** `ScoringSystem` uses `String` raw value for Codable/SwiftData persistence. `PersistedMatch.scoringSystemRaw` stores `"standard21"` or `"threeByFifteen"`. `CodableMatchState.scoringSystem` is typed as `ScoringSystem?`. The entire serialization chain assumes a finite set of enum cases.
**Consequences:** Cannot add custom rules without either breaking the enum's raw value conformance or redesigning the persistence layer. Breaking `Codable` synthesis means manually implementing `init(from:)` and `encode(to:)`, which is error-prone and breaks the existing test-passing JSON round-trips.
**Prevention:**
- Option 1 (recommended): Keep `ScoringSystem` as-is and add a SEPARATE `customRules: ScoringRules?` field to `MatchState`. When `customRules != nil`, it overrides `ScoringRules.rules(for: scoringSystem)`. This is backward compatible -- existing matches with `scoringSystem: .standard21` continue to work.
- Modify the `scoringRules` computed property in `MatchState`:
  ```swift
  public var scoringRules: ScoringRules {
      customRules ?? ScoringRules.rules(for: scoringSystem)
  }
  ```
- Add `.custom` to `ScoringSystem` as a sentinel that indicates "look at customRules field":
  ```swift
  case custom // no raw value conflict since "custom" is a valid string
  ```
- In `CodableMatchState`, add `customRules: ScoringRules?` (optional, nil by default -- backward compatible)
- In `PersistedMatch`, add `customRulesJSON: Data?` (optional, nil by default -- CloudKit safe)
- Option 2 (NOT recommended): Change `ScoringSystem` to `ScoringSystem.custom(ScoringRules)` with manual Codable -- too much breakage.
**Detection:** If adding a new `ScoringSystem` case causes test failures in Codable round-trip tests, the approach is wrong.

### Critical Pitfall 3.3: Custom Rules Must Round-Trip Through All Serialization Layers

**Risk Level:** CRITICAL
**What goes wrong:** A custom scoring match state must survive ALL of these serialization paths:
1. `MatchState` -> `CodableMatchState` -> JSON -> `stateJSON` on `PersistedMatch` (crash recovery)
2. `MatchState` -> `CodableMatchState` -> `SyncPayload` -> WatchConnectivity dictionary -> Watch (real-time sync)
3. `PersistedMatch` -> CloudKit -> another device -> `PersistedMatch` (cross-device sync)

Each path has different constraints. The `SyncPayload` uses dictionary keys. CloudKit has field-level sync. `stateJSON` is a blob.
**Why it happens in this codebase:** Three independent serialization paths were built for a fixed set of scoring systems. Adding dynamic user-defined rules means the rules themselves must be serialized, not just a system identifier.
**Consequences:** Custom rules survive crash recovery (path 1) but not Watch sync (path 2) because `SyncPayload.toDictionary()` does not include the custom rules fields. The Watch falls back to `.standard21` rules and shows wrong game state.
**Prevention:**
- Add `ScoringRules` conformance to `Codable` (it is currently just `Sendable, Equatable` -- NOT `Codable`)
- Add `customRules: ScoringRules?` to `CodableMatchState`
- Verify `SyncPayload` serializes the full `CodableMatchState` JSON (if it does, custom rules are automatically included)
- If `SyncPayload` uses manual dictionary keys, add the custom rules data
- Write a round-trip test for EACH serialization path with custom rules
**Detection:** Create a match with custom rules (e.g., 11 points, best of 3). Score a few points. Kill the app. Relaunch. Verify the custom rules are preserved. Then check the Watch -- does it show the right points-to-win?

### Moderate Pitfall 3.4: PersistedMatch.scoringSystemRaw Cannot Represent Custom Rules Inline

**Risk Level:** MODERATE
**What goes wrong:** `PersistedMatch.scoringSystemRaw` is a `String` that stores `"standard21"` or `"threeByFifteen"`. For custom rules, what does it store? `"custom"` is semantically correct but loses the actual rule values. The rule values are in `stateJSON` (inside the `CodableMatchState` blob), but `stateJSON` is opaque -- it cannot be queried for list rendering.
**Why it happens:** The denormalized fields on `PersistedMatch` (`game1ScoreA`, `winnerSide`, etc.) exist for fast list rendering without deserializing `stateJSON`. Custom rules need similar denormalization.
**Consequences:** Match history list shows "Custom" with no details. User cannot distinguish between different custom formats in the list view.
**Prevention:**
- Store `scoringSystemRaw = "custom"` for identifier
- Add `customRulesJSON: Data?` to `PersistedMatch` (CloudKit-safe, optional, nil for standard/3x15)
- For list rendering, add `pointsToWinDisplay: Int?` (optional, nil for standard formats, populated for custom) so the list view can show "Custom (to 11, best of 3)" without deserializing
- Alternatively, encode a short human-readable label like `"11pt-bo3"` in `scoringSystemRaw` -- but this makes parsing fragile
**Detection:** If match history shows all custom matches as identical "Custom" entries with no distinguishing info, the denormalization is insufficient.

### Moderate Pitfall 3.5: Custom Rules UI Builder Can Create Degenerate Games

**Risk Level:** MODERATE
**What goes wrong:** A user creates a format with `pointsToWin: 1, maxGames: 1, deuceThreshold: 1, capScore: 1`. The match ends on the first point. While technically valid, it makes Hawk Eye challenges impossible (no time to capture footage) and Live Activity updates pointless. Or: `pointsToWin: 100, maxGames: 9` creates a match that lasts 3+ hours and fills the `games` array well beyond what `PersistedMatch` can store (only 5 game score fields).
**Consequences:** Edge-case degenerate formats that technically work but break UX assumptions or storage.
**Prevention:**
- Set reasonable UI bounds: pointsToWin 5-31, maxGames 1-9, gamesToWin 1-5
- If `maxGames > 5`, the `PersistedMatch` denormalized game score fields (game1-5) are insufficient. Either:
  - Cap maxGames at 5 in the UI
  - Or rely on `stateJSON` for games 6+ and accept that list rendering cannot show those scores without deserialization
- Warn the user if the expected match duration exceeds 2 hours based on typical rally length (~15 seconds per point)
**Detection:** Try to persist a match with 7 games completed. If `game6ScoreA/B` and `game7ScoreA/B` fields do not exist, data is silently lost.

### Moderate Pitfall 3.6: Watch Does Not Know How to Display Custom Format Names

**Risk Level:** MODERATE
**What goes wrong:** The Watch scoring view shows game state assuming either "21-pt" or "15-pt" format. A custom format (e.g., "to 11, best of 3") has no built-in display label. The Watch receives the match state via WatchConnectivity but has no UI to show custom format metadata.
**Consequences:** Watch shows score "8-6" with no indication that the game ends at 11. User does not know if the game is almost over or barely started.
**Prevention:**
- Include `pointsToWin` in the Watch sync payload (or derive it from the custom rules)
- Watch display should show "Game 2 of 3 (to 11)" dynamically, not assume 21 or 15
- Already partially relevant for 3x15 -- verify the Watch handles the existing "to 15" display correctly before adding custom formats
**Detection:** Set up a custom format match and check the Watch display. If it shows "21" anywhere, the format is hardcoded.

---

## Area 4: CloudKit + Backward Compatibility

### Critical Pitfall 4.1: New Fields Without Defaults Break Older App Versions

**Risk Level:** CRITICAL
**What goes wrong:** When a v1.3 user creates a match with custom scoring rules, the `PersistedMatch` record syncs via CloudKit to their iPad running v1.2. The v1.2 app does not have `customRulesJSON` or `pointsToWinDisplay` fields in its `@Model`. SwiftData/CloudKit handles unknown fields gracefully (ignores them), so the record loads -- but the v1.2 code reads `scoringSystemRaw = "custom"` and tries `ScoringSystem(rawValue: "custom")` which returns `nil` because v1.2's `ScoringSystem` enum does not have a `.custom` case.
**Why it happens in this codebase:** `CodableMatchState.scoringSystem` is decoded from JSON. If the raw value is `"custom"` and the v1.2 decoder does not recognize it, decoding fails entirely -- the match's `stateJSON` cannot be deserialized, so the match appears as a corrupt entry in match history.
**Consequences:** Users running v1.2 on one device and v1.3 on another see custom-format matches as broken/empty entries. Match history is inconsistent across devices.
**Prevention:**
- In `CodableMatchState`, decode `scoringSystem` with a fallback: `scoringSystem = (try? container.decode(ScoringSystem.self, forKey: .scoringSystem)) ?? .standard21`. This already exists (`var scoringSystem: ScoringSystem?` with nil defaulting to `.standard21`) but the `toMatchState()` method must also handle the case where the scoring system is unknown.
- In v1.3, when creating custom-format matches, store `scoringSystemRaw = "custom"` on `PersistedMatch`
- v1.2 users see the match with `scoringSystemRaw = "custom"`, which their `ScoringSystem(rawValue:)` returns nil for. Their `CodableMatchState` decoding should fall back to `.standard21` -- the match displays with wrong rules but does not crash
- Better: in v1.2, if `scoringSystemRaw` is unrecognized, show the match as "Unknown format" in the list view rather than trying to decode and display it
- This is a backward-compatibility concern for v1.2 users who have not updated. In practice, most users auto-update, so the window is small.
**Detection:** Install v1.2 on one device, v1.3 on another, same iCloud account. Create a custom-format match on v1.3 and verify v1.2 does not crash.

### Critical Pitfall 4.2: ScoringRules Is Not Codable -- Adding Codable May Change JSON Shape

**Risk Level:** HIGH
**What goes wrong:** `ScoringRules` is currently `Sendable, Equatable` but NOT `Codable`. To serialize custom rules in `CodableMatchState` and `PersistedMatch`, it must become `Codable`. Adding `Codable` conformance to `ScoringRules` is straightforward (it is a struct with all `let` fields of `Codable` types), but the JSON keys will be auto-generated from property names. If property names change later (e.g., renaming `midGameSwitchPoint` to `changeSidesAt`), previously serialized JSON cannot be decoded.
**Consequences:** JSON schema for custom rules is locked at the time of v1.3 release. Property names become part of the public API.
**Prevention:**
- Add `Codable` conformance with explicit `CodingKeys` enum to lock the JSON field names
- Use short, stable key names: `ptw` (pointsToWin), `dt` (deuceThreshold), `cs` (capScore), `gtw` (gamesToWin), `mg` (maxGames), `msp` (midGameSwitchPoint) -- or use the full names, but commit to them permanently
- Write a test that encodes a `ScoringRules` instance, hardcodes the expected JSON string, and verifies they match -- this prevents accidental key name changes from breaking serialization
**Detection:** Change a property name and watch the serialization test fail.

---

## Area 5: Cross-Cutting Integration Pitfalls

### Critical Pitfall 5.1: 53 Existing Tests Must Pass Without Modification

**Risk Level:** CRITICAL
**What goes wrong:** The ScoringEngine package has 44+ tests (8 test files) testing singles, doubles, mixed, deuce/cap, service rotation, undo, game transitions, and 3x15 format. Adding custom scoring MUST NOT break any of these. The danger is:
1. Making `ScoringRules: Codable` adds a requirement that could conflict with `Sendable` (it will not, but verify)
2. Adding `customRules: ScoringRules?` to `MatchState` changes the struct layout, which changes `Equatable` conformance (custom Equatable is already implemented, but must include new fields)
3. Adding `.custom` to `ScoringSystem` enum -- every `switch` on `ScoringSystem` throughout the codebase must handle it or fail to compile (good -- exhaustive switch catches it)
**Prevention:**
- Run all tests BEFORE any changes (baseline)
- Add `customRules` to the custom `Equatable` implementation in MatchState
- Add `.custom` case to `ScoringSystem` -- let the compiler find every `switch` that needs updating
- The `ScoringRules.rules(for:)` static method must handle `.custom` -- either `fatalError("Use customRules instead")` or return a sensible default
- Run tests after EVERY change to Types.swift or MatchState.swift
**Detection:** CI test failures. Do not batch changes -- commit after each logical change and run tests.

### Critical Pitfall 5.2: Multi-Cam + Audio Increases App Binary Size and Entitlements

**Risk Level:** MODERATE
**What goes wrong:** Adding `AVCaptureMultiCamSession`, `AVCaptureAudioDataOutput`, and Accelerate framework `vDSP` functions does not add binary size (these are system frameworks). But adding the `NSMicrophoneUsageDescription` key and requesting microphone permission may trigger additional App Store review scrutiny. If the permission description is vague ("to improve video quality"), Apple may reject it.
**Consequences:** App Store rejection during review. Delays release.
**Prevention:**
- Use a clear, specific permission description: "Badminton Eye records audio alongside video to automatically synchronize footage from multiple camera angles for Hawk Eye challenge analysis."
- Request microphone permission only when the user first attempts multi-angle analysis, not at app launch
- If the user denies microphone permission, fall back to timestamp-based alignment (less accurate but functional)
**Detection:** Test the permission flow on a fresh install. Verify the description appears correctly.

### Moderate Pitfall 5.3: ResultFusionService Assumes Same Calibration for Both Angles

**Risk Level:** MODERATE
**What goes wrong:** `ResultFusionService.fuse()` takes `[HawkEyeResult]` and does a weighted average of `landingPoint` coordinates. But `landingPoint` is in court coordinates (after homography transform). If both cameras are properly calibrated, their court coordinates should agree. If one camera has stale calibration, its court coordinates are shifted, and the weighted average lands between the correct and incorrect positions -- potentially flipping an "in" call to "out" or vice versa.
**Consequences:** Multi-camera fusion DECREASES accuracy when one camera is miscalibrated. The fused result is neither the correct single-camera result nor a genuine multi-angle improvement.
**Prevention:**
- Add disagreement detection to `ResultFusionService`: if the two `landingPoint` values differ by more than a threshold (e.g., 15cm in court coordinates), flag the result as low-confidence rather than averaging
- If landing results disagree (one says "in", other says "out"), do NOT average -- use the higher-confidence single result and flag the disagreement for the user
- Add a `fusionQuality: FusionQuality` (.high, .degraded, .singleAngle) to `HawkEyeResult` so the UI can show "Multi-angle result (high confidence)" vs "Cameras disagree -- showing primary angle"
**Detection:** Deliberately miscalibrate one camera in testing and verify that the fusion service does not produce a worse result than single-camera.

### Moderate Pitfall 5.4: Feature Interaction -- Custom Scoring + Multi-Cam + Watch Sync Payload Size

**Risk Level:** MODERATE
**What goes wrong:** Adding custom rules JSON to the sync payload, plus multi-camera status metadata, grows the WatchConnectivity payload. `applicationContext` has an unofficial ~256KB limit. The current payload is small (<1KB), but if custom rules include a name/description field and multi-cam adds calibration data, it could grow.
**Prevention:**
- Keep WatchConnectivity payload minimal: scoring state + customRules (if any) + format metadata
- Do NOT send camera/multi-cam state to Watch -- the Watch does not need it
- Custom rules are 6 integers (~100 bytes serialized) -- negligible
- This is unlikely to be a real problem for v1.3 but monitor payload size
**Detection:** Log payload size on each `sendMessage` / `updateApplicationContext` call. Alert if >10KB.

### Minor Pitfall 5.5: Custom Format Picker in MatchSetupView Complicates the Setup Flow

**Risk Level:** MINOR
**What goes wrong:** `MatchSetupView` currently has a clean two-option picker for scoring system (standard 21 / BWF 3x15). Adding a "Custom" option requires expanding the UI with number pickers for points-to-win, games-to-win, deuce behavior, etc. If presented inline, the setup view becomes overwhelming. If presented as a sheet, it adds a navigation step.
**Prevention:**
- Add "Custom" as a third option in the scoring system picker
- When "Custom" is selected, expand a section below with the configuration fields (points per game, number of games, deuce on/off, cap score)
- Use sensible defaults for the custom builder that mirror standard 21 -- user adjusts from there
- Include presets: "Quick match (11-pt, best of 1)", "Training (15-pt, best of 3)", "Custom..." -- most users will pick a preset rather than building from scratch
- Allow saving custom formats for reuse (persist as SwiftData model `CustomScoringFormat`)
**Detection:** User testing. If users take >10 seconds to set up a custom format, the UX needs simplification.

---

## Phase-Specific Warnings

| Phase | Feature | Likely Pitfall | Severity | Mitigation |
|-------|---------|---------------|----------|------------|
| 1 | Custom Scoring | ScoringSystem enum cannot represent custom (3.2) | CRITICAL | Add .custom case + customRules field on MatchState |
| 1 | Custom Scoring | ScoringRules needs validated init (3.1) | CRITICAL | Failable initializer with constraint checks |
| 1 | Custom Scoring | Custom rules must survive all 3 serialization paths (3.3) | CRITICAL | Add Codable to ScoringRules, test each path |
| 1 | Custom Scoring | CloudKit backward compat for v1.2 devices (4.1) | CRITICAL | Fallback decoding for unknown scoring system |
| 1 | Custom Scoring | 53 tests must pass (5.1) | CRITICAL | Run tests after every change |
| 2 | Multi-Cam | A12+ only, camera pair validation (1.1) | CRITICAL | Probe canAddInput for specific pairs |
| 2 | Multi-Cam | FPS limits in multi-cam mode (1.2) | CRITICAL | Use supportedMultiCamVideoFormats, asymmetric FPS |
| 2 | Multi-Cam | Thermal throttling (1.3) | CRITICAL | Thermal state monitoring, graceful degradation |
| 2 | Multi-Cam | Dual-buffer memory explosion (1.4) | CRITICAL | Asymmetric FPS, disk-write secondary, memory pressure observer |
| 2 | Multi-Cam | VideoCaptureManager not multi-cam-aware (1.5) | MODERATE | New MultiCamCaptureManager class, protocol abstraction |
| 3 | Audio Sync | No audio capture in current pipeline (2.1) | CRITICAL | Add AVCaptureAudioDataOutput, separate audio buffer |
| 3 | Audio Sync | Same-device multi-cam has same microphone (2.4) | MODERATE | Use audio sync only for two-device alignment |
| 3 | Audio Sync | vDSP cross-correlation precision (2.2) | HIGH | Bandpass filter, sub-sample interpolation, SNR validation |
| 3 | Audio Sync | FFT implementation pitfalls (2.3) | MODERATE | Use Float, pre-allocate, FFT not time-domain conv |
| 3 | Integration | ResultFusionService with miscalibrated cameras (5.3) | MODERATE | Disagreement detection, do not average disagreeing results |

## Warning Signs Checklist

Use these during development to detect pitfalls early:

- [ ] `ScoringRules` init accepts `pointsToWin: 0` or `capScore < pointsToWin` -> Pitfall 3.1
- [ ] Adding `.custom` to `ScoringSystem` causes Codable compilation errors -> Pitfall 3.2
- [ ] Custom rules match works on iPhone but Watch shows wrong pointsToWin -> Pitfall 3.3/3.6
- [ ] `PersistedMatch` on v1.2 crashes when receiving v1.3 CloudKit record -> Pitfall 4.1
- [ ] Any of the 53 existing tests fail after ScoringEngine changes -> Pitfall 5.1
- [ ] `isMultiCamSupported` is true but `canAddInput` fails for chosen camera pair -> Pitfall 1.1
- [ ] Multi-cam session starts but actual FPS is lower than requested -> Pitfall 1.2
- [ ] App killed by Jetsam during multi-cam recording (check crash logs for `EXC_RESOURCE`) -> Pitfall 1.4
- [ ] Thermal state reaches `.serious` within 5 minutes of dual-cam capture -> Pitfall 1.3
- [ ] Cross-correlation always returns zero offset on single-device multi-cam -> Pitfall 2.4
- [ ] Cross-correlation peak SNR < 3:1 -> Pitfall 2.2
- [ ] `vDSP` correlation takes > 200ms for 10-second clips -> Pitfall 2.3
- [ ] Two cameras disagree on in/out but fusion averages to wrong result -> Pitfall 5.3
- [ ] Microphone permission description rejected by App Store review -> Pitfall 5.2

## Sources

- Codebase analysis: `ScoringEngine/Sources/ScoringEngine/Types.swift` (ScoringRules struct, ScoringSystem enum)
- Codebase analysis: `ScoringEngine/Sources/ScoringEngine/MatchState.swift` (scoringRules computed property, factory methods)
- Codebase analysis: `ScoringEngine/Sources/ScoringEngine/MatchEngine.swift` (apply event logic)
- Codebase analysis: `ScoringEngine/Sources/ScoringEngine/BWFRules.swift` (parameterized rule computations)
- Codebase analysis: `BadmintonEye/Models/CodableMatchState.swift` (serialization mirror, backward compat handling)
- Codebase analysis: `BadmintonEye/Models/SwiftDataModels.swift` (PersistedMatch schema, game1-5 score fields)
- Codebase analysis: `BadmintonEye/Services/VideoCaptureManager.swift` (single AVCaptureSession, no audio, configureHighFPSFormat)
- Codebase analysis: `BadmintonEye/Services/CircularFrameBuffer.swift` (CMSampleBuffer array, time-based eviction, no memory ceiling)
- Codebase analysis: `BadmintonEye/Services/ResultFusionService.swift` (weighted average fusion, no disagreement detection)
- Codebase analysis: `BadmintonEye/Services/HawkEyePipeline.swift` (single video URL input, frame-skip logic)
- Codebase analysis: `BadmintonEye/ViewModels/LiveMatchViewModel.swift` (all 3 serialization paths, updateGameScores indexing)
- Codebase analysis: `ScoringEngine/Tests/ScoringEngineTests/ThreeByFifteenTests.swift` (existing parameterized test pattern)
- Apple AVCaptureMultiCamSession documentation (training data, MEDIUM confidence -- API is stable since iOS 13 but device-specific behavior varies)
- Apple Accelerate vDSP documentation (training data, HIGH confidence -- mature API, minimal changes since iOS 4)
- Apple SwiftData + CloudKit migration constraints (training data, HIGH confidence -- well-documented limitation)
- Apple AVCaptureDataOutputSynchronizer documentation (training data, MEDIUM confidence)
- Apple thermal state monitoring API (training data, HIGH confidence -- stable since iOS 11)
