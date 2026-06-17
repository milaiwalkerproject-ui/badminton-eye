# Badminton Eye — Travel Handoff (MacBook)

**Written:** 2026-06-16 by the David Overseer (running on the Mac Studio).
**For:** continuing this project on the MacBook (Apple Silicon / arm64) while traveling, away from the Mac Studio for ~1 month.
**Read this first.** It is self-contained — a fresh Claude/Cursor/terminal session on the MacBook can resume from this file alone.

---

## 1. What this project is

**Badminton Eye** — an iPhone app (SwiftUI + SwiftData + CoreML) that assists badminton scoring and replay. A "System 2" on-device model (TrackNetV3 shuttle tracker → RallyWinnerClassifier) suggests who won each rally, behind a **conservative 0.92 confidence gate** (it stays silent rather than guess). A separate offline **"hawkeye" Python pipeline** trains that classifier from labeled rally footage (the training flywheel).

- **Repo (canonical, on the Studio):** `/Users/milai/Developer/badminton-eye`
- **GitHub:** `github.com/milaiwalkerproject-ui/badminton-eye` — `main` = `0ca8938` (fully pushed; a clone is complete and self-contained, CoreML models included, ~2.7 GB).
- **iOS app:** `BadmintonEye/` (Xcode project) + `ScoringEngine/` (SwiftPM). **hawkeye pipeline:** `hawkeye/` (Python).

## 2. Current state (all shipped, tested, pushed)

`main = origin/main = 0ca8938`. Recent work, newest first:
- `0ca8938` — five UX "trust-breaker" fixes (badge/exit collision, broken Language row, dead Edit Highlight, placeholder-name pollution in recents, **Resume-Match prompt** so in-progress matches no longer vanish). Tests 59/59 app + 143/143 engine.
- `b0088d0` — video-import fix: streams library videos to disk (no RAM blowup), "Preparing video…" progress, real error alerts, replay URL fix.
- `d40ff2b` — first-launch lag fix (filtered Players query, `.externalStorage` blobs, thumbnail avatars; SwiftData migration verified twice).
- `2cb1b73` / `4599121` / `29b5a5f` — the **4-fix hawkeye pipeline overhaul**: orientation-aware both-angle support (ADR-0001), non-rally auto-skip, court-mask post-filter, clip-display padding. Existing 7 labels proven untouched (bit-for-bit over 6,426 rallies).

**The app on the iPhone:** last Release install was `0ca8938`. **Free-Apple-ID signing → expires ~2026-06-18.** After that the app stops launching until rebuilt+reinstalled. (This is the core reason for the MacBook build plan in §5.)

## 3. THE TRAVEL MISSION (your primary task on the MacBook)

**Label your own end-on footage, offline, using the lite bundle this file ships inside.** Those labels are the highest-value data in the whole project — they are the end-on training set that (a) replaces the app's current fake "demo mode" analysis with real analysis, and (b) opens the inference gate so the model can predict winners on end-on (phone-tripod) footage. **System-2 real accuracy is still UNMEASURED** — your labels are the gate to measuring it.

### How to label (this bundle — fully offline, no Studio, no internet)
1. This folder (`labeling-bundle-lite/`, ~280 MB) is already on the MacBook (you copied it over). It is **Apple Silicon only**.
2. Double-click **`setup.command`** → first run builds an offline Python env from the bundled wheels and opens the labeler. (Gatekeeper blocks it → right-click → **Open** once.)
3. Label each rally — keys: **A** = near/bottom player won · **B** = far/top player won · **N** = not a rally · **S** = skip if unclear · **R** = replay · **Q** = save & quit.
4. ~102 of your own end-on rallies (videos IMG_4665–4668) are queued. Your labels accumulate in:
   `labeling-bundle-lite/data/processed/annotations_human_holdout.jsonl`

### Sync your labels back (when you can reach the Studio again)
That one file **IS the work product.** When you have a connection to the Studio (or to me), send/copy back:
`labeling-bundle-lite/data/processed/annotations_human_holdout.jsonl`
The Overseer merges it into `hawkeye/data/processed/` and runs the flywheel: `build_training_set → retrain (now including end-on) → calibrate_confidence → holdout_eval`. **Do not lose this file** — it's hand-labeled ground truth that can't be regenerated.

## 4. What you CAN'T do on the MacBook during travel (needs the Studio)
- TrackNet **extraction** on new videos (GPU/compute pipeline lives on the Studio). So the **new clips still in your Photos can't be labeled on the trip** — they have no trajectories yet. AirDrop them somewhere safe; we extract them when you're back or can remote into the Studio.
- The full 116-video side-on corpus (the 21 GB bundle stays on the Studio). The lite bundle's 4 end-on games are the priority anyway.
- The David Overseer (me) runs on the Studio. If you can remote-control the Studio over the internet, everything resumes normally; if not, you're MacBook-standalone for labeling.

## 5. OPTIONAL: full dev environment on the MacBook (build/test the app yourself)
You signed Xcode into the same Apple ID (`milaiwalkerproject@gmail.com`). Because your **phone travels with the MacBook**, you can build+install over USB with no Studio dependency, and the 7-day expiry stops mattering (just rebuild on the spot). Do the one-time setup while you still have internet:
1. Install **Xcode** (App Store, ~15 GB — do early).
2. `git clone https://github.com/milaiwalkerproject-ui/badminton-eye.git` (~2.7 GB, models included).
3. Xcode → Settings → Accounts → add the Apple ID; open the project, set Team under Signing & Capabilities (automatic).
4. Plug in the iPhone → Run → builds + installs over USB.

**Signing facts (important):** automatic signing, **Team = `4ATCU5B9J2`** (NOT `R56JX7A747` — that's the cert-name suffix; passing it as the team ID fails with "No Account for Team"). Free Apple ID = 7-day app expiry. **Mild risk:** a different signing cert can occasionally make iOS treat the install as new and wipe local match data — back up anything important; same-team usually updates in place.

To also run the **labeler/pipeline natively** on the MacBook (beyond the lite bundle): the repo has the models; create a Python 3.11 venv, `pip install opencv-python numpy` (the standard `opencv-python` wheel HAS GUI support — do NOT use `opencv-python-headless`), set `PYTHONPATH=hawkeye/src`, run `python -m hawkeye.annotate.holdout_label`.

## 6. Open decisions waiting for you (no decay, decide anytime)
1. **Full-match analysis — wave 1 go/no-go (~2.5–3 wks).** Design is complete + review-hardened: `agents/Overseer/FULLMATCH-ANALYSIS-DESIGN.md`. Replaces demo mode with real on-device TrackNet over full 20–30 min matches (chunked, resumable, thermal/storage-guarded), and **puts "Who won? A/B" labeling INTO the app on your phone** — which would make labeling fully portable (no Mac at all). Binding refinements already locked: canonical frame index `f=round(t×30)`; import-flow training exports tagged `unmasked_import:true` and quarantined until court-masked.
2. **Design-review tiers** (`agents/Overseer/DESIGN-REVIEW.md`, 23 screenshots): (a) restructure — one match = score+video+highlights on one screen, hero "Start Match"; (b) AI confidence-posture redesign; (c) **ship the Live Activity** — it's ~90% built but disabled behind the free-Apple-ID flag.
3. **Court masks for end-on videos** — needed before end-on trajectories feed training (adjacent-court shuttle pollution). Can be done agent-side from frames (no GUI) when back on the Studio.

## 7. Key context / gotchas (so a fresh session doesn't repeat mistakes)
- **Orientation architecture (ADR-0001):** end-on footage splits players near/far (image-Y), side-on splits left/right (image-X). The model normalizes the player-separation axis to X (`end_on: side = 1 − image_y`, A=near) while **apex/gravity features stay on raw image-Y in both orientations**. side_on is bit-for-bit identical to the old behavior. **End-on inference is HARD-GATED** until a retrain includes end-on labels (`meta.trained_orientations`) — your travel labels are what open it.
- **iOS gap (known):** the on-device Swift featurizer has no orientation concept yet → it does zero-shot end-on on your own footage today, mitigated only by the 0.92 gate. On-device gate parity is a queued wave.
- **Stored convention:** winner is `sideA`/`sideB`; meaning bound by `(winner, orientation)`. Side-on A=left/B=right; end-on A=near/B=far.
- **History:** keep this project OUT of iCloud Desktop (prior data-loss incident) — it lives in `~/Developer`, pushed to GitHub as the backup.
- **Thunderbolt Bridge between the two Macs was NOT actually active** (`bridge0` had no IP); large transfers fell back to slow Wi-Fi. That's why labeling went the small-proxy route.

## 8. To resume with a Claude/David session on the MacBook
Open a session in the cloned repo (or in this bundle for labeling-only) and paste:
> "Read HANDOFF.md. I'm continuing the badminton-eye project on my MacBook while traveling. My active task is labeling the end-on footage in this bundle; help me run it and answer questions. The Mac Studio (and the David Overseer) are unreachable unless I say I can remote in."

The Studio-side Overseer keeps the full record (LEDGER, chat.md, NEXT.md, long-term memory) and resumes automatically whenever you reconnect.

---
*Files referenced live on the Mac Studio under `/Users/milai/Developer/badminton-eye` and `~/.david/workspaces/badminton-eye/agents/Overseer/`. This bundle is self-sufficient for the labeling mission.*
