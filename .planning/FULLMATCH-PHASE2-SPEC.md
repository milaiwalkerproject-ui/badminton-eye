# Wave 1 Phase 2 — FullMatchAnalyzer implementation spec

Recon (workflow wf_ba127195-724, 2026-07-06) distilled to an implementable
contract. Read with FULLMATCH-WAVE1-PLAN.md.

## Detector facts (TrackNetShuttleDetector.swift)

- `detect(frames: [CVPixelBuffer], background: CVPixelBuffer) async throws ->
  [TrackNetWindowObservation]` — exactly 8 frames, oldest first, ALREADY
  512×288. Returns 8 observations (normalized [0,1] position or nil, conf,
  windowFrameIndex). Input tensor (1,27,288,512) f32 planar
  (f0RGB…f7RGB,bgRGB); feature "frames", output "heatmap" (1,8,288,512).
- Model: bundled TrackNetV3.mlmodelc, computeUnits .all, threshold 0.5.
- Current hot-path inefficiencies (fix in the batch path, do NOT touch the
  live path): fresh 15.2 MiB MLMultiArray per call (line ~145); `writeRGB`
  does a CIContext GPU→CPU readback + 147k-iteration per-pixel Swift loop ×9
  per window; scalar argmax over 1.18M floats.
- Batch path design: BYPASS TrackNetWindowAdapter (its stride-4 cache +
  call-order frameIndex are wrong for offline). Non-overlapping stride-8
  windows; harvest all 8 observations per predict; trailing <8 remainder
  dropped (python parity). Pipelining/vImage/outputBackings are OPTIMIZATIONS
  — a correct simple v1 using detector.detect() as-is is acceptable if
  AVAssetReader decodes straight to 512×288 32BGRA via outputSettings
  (kCVPixelBufferWidthKey/HeightKey/PixelFormatTypeKey — VideoToolbox scales,
  eliminating the adapter's CI preprocess entirely). Background v1: median is
  ideal (python uses global median over ≤60 sampled frames, /255); the first
  frame of the video is the v0 stand-in (matches live path TODO(bg-median)).

## Video reading (repo precedents)

- AVAssetReader precedent: HawkEyePipeline.swift:214-260 (BGRA outputSettings,
  copyNextSampleBuffer drain). Do NOT copy its sequential frameIndex or its
  150-frame cap.
- Swift 6.1: `@preconcurrency import AVFoundation` everywhere; keep
  reader/CMSampleBuffer confined to one isolated scope; emit only Sendable
  values. No actors hold AV state today; either an actor whose single method
  does open→drain→emit, or the HawkEyePipeline pattern (@Observable
  @unchecked Sendable class + nonisolated async worker + MainActor.run for
  progress).
- Chunking: AVAssetReader is single-pass; a resume = NEW reader with
  `reader.timeRange` set (CMTimeRange from checkpoint) before startReading().
- PTS: t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb)).
  FootageWriter startSession(atSourceTime: first PTS) normalizes file
  timelines to ~0, but do NOT hard-code that: subtract the first sample's PTS
  defensively (imported videos may not start at 0).
- Canonical index: f = round(t_rel × 30). 60 fps sources map ~2 frames per f:
  DEDUPE POLICY = keep the max-confidence detection per f (decided Phase 2).

## Checkpoint store (clone TrainingExportWriter pattern)

`FullMatchAnalysisStore` enum namespace → `Application Support/FullMatchAnalysis/`:
- `<videoStem>.detections.jsonl` — one line per COMPLETED chunk:
  `{"schema":1,"chunk":N,"fStart":..,"fEnd":..,"detections":[{"f":..,"x":..,"y":..,"conf":..,"vis":..},..]}`
  Append-only, atomic first write, FileHandle append after; tolerant read
  (skip torn/malformed lines) = resume state. Chunk complete ⇔ line present.
- Resume: highest contiguous chunk index from file → next timeRange.
- Chunk size: ~30 s of video per chunk (900 canonical frames) — small enough
  that a kill loses ≤30 s of work, big enough that per-chunk reader setup
  amortizes.

## Guards

- Thermal: ProcessInfo.processInfo.thermalState; precedent
  MultiCamCaptureManager.swift:17,40-46,182-199 uses #selector observer — in
  async context prefer polling between chunks + NotificationCenter async
  sequence. Pause when ≥ .serious, resume when ≤ .fair.
- Storage: volumeAvailableCapacityForImportantUsage precheck (new API surface;
  require e.g. 500 MB free).
- Foreground: UIApplication.shared.isIdleTimerDisabled while analyzing
  (set/clear from the UI layer, MainActor).
- Simulator: Footage/ is empty on simulator (GameRecordingService no-ops);
  tests must inject fixture data, not expect real videos.

## Rally segmentation (Phase 3, port EXACTLY — python extract_rallies.py:91-124)

- Input: per-frame `{f,x,y,conf,vis}`; skip vis=false entirely.
- New rally when gap_s = (f − last_vis_f)/fps **strictly >** 1.0.
- Keep rally when (last_f − first_f)/fps **>=** 1.5.
- start/end snap exactly to first/last VISIBLE frame; no padding in data
  (annotate UI adds ~2 s display padding downstream).
- rally_id = 0-based over KEPT rallies only, assigned in a FINAL whole-video
  pass (never per-chunk — dropped short rallies must not consume ids).
- GAP_SAME_RALLY_S=0.5 in python is dead code; port the code, not docstring.
- Export `trajectories/<stem>.json`:
  `{"video":stem,"fps":30.0,"orientation":...,"rallies":[{"rally_id","start_frame","end_frame","trajectory":[{"f","x","y","conf","vis"},..]},..]}`
  MUST write "fps": 30.0 because f is canonical-30 (python consumers compute
  time as f_delta/fps, defaulting 30). x,y normalized image coords (y down),
  rounded 4dp in python (rounding optional in Swift). Always write vis field.

## Consumers to feed later

- HitDetector.confidentRallyEnd(samples:minQuality:) takes [TrackSample]
  (t, court: CourtPoint?, imageY, conf) — needs court-space via calibration
  homography; analyzer output is image-space, conversion happens where
  calibration is available.
- ClassifierRallyScorer.featurize is image-space — analyzer detections feed
  it directly (no orientation parameter yet — known gap, ADR-0001).

## UI surface (minimal Phase 2)

FootageDetailView game section: "Analyze Match" row (disabled when video
missing) → progress (chunk M/N or %) → done state persisting nothing to
SwiftData yet (detections live in the store file; SwiftData analysis-state
field can come with Phase 3's rally list UI). All new strings → 9 locales.
