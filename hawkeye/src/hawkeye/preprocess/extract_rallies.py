"""Extract rally trajectories from a video using TrackNetV3.

Pipeline:
  - decode frames @ source FPS (OpenCV)
  - resize to 288x512
  - compute rolling-median background (5s window) for bg_mode='concat'
  - slide an 8-frame window, run TrackNet, argmax each heatmap, threshold 0.5
  - group consecutive visible detections into rallies (gap<0.5s = same; >1s = boundary)
  - write JSON per video to data/processed/trajectories/<video_id>.json

The output JSON carries a top-level ``orientation`` field ("side_on"|"end_on",
ADR-0001) resolved from --orientation > the data/processed/orientation.json
sidecar > "side_on". Existing trajectory JSONs without the field are side_on
by definition and are never rewritten.

Usage:
    python -m hawkeye.preprocess.extract_rallies <video_path> [--out-dir DIR]
                                                 [--orientation side_on|end_on]
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from collections import deque
from pathlib import Path

import cv2
import numpy as np
import torch

from ..orientation import VALID_ORIENTATIONS, load_orientation_map, resolve_orientation

REPO_ROOT = Path(__file__).resolve().parents[3]
TRACKNET_REPO = REPO_ROOT / "third_party" / "TrackNetV3"
CKPT_PATH = TRACKNET_REPO / "ckpts" / "TrackNet_best.pt"
DEFAULT_OUT_DIR = REPO_ROOT / "data" / "processed" / "trajectories"

SEQ_LEN = 8
IN_CH = SEQ_LEN * 3 + 3
H, W = 288, 512
HEATMAP_THRESH = 0.5
GAP_SAME_RALLY_S = 0.5
GAP_BOUNDARY_S = 1.0
MIN_RALLY_S = 1.5


def _device() -> torch.device:
    if torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def load_tracknet() -> torch.nn.Module:
    sys.path.insert(0, str(TRACKNET_REPO))
    from model import TrackNet  # type: ignore
    ckpt = torch.load(CKPT_PATH, map_location="cpu", weights_only=False)
    sd = ckpt["model"] if isinstance(ckpt, dict) and "model" in ckpt else ckpt
    m = TrackNet(in_dim=IN_CH, out_dim=SEQ_LEN)
    m.load_state_dict(sd, strict=True)
    m.eval()
    return m.to(_device())


def iter_frames(video_path: Path):
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise RuntimeError(f"cannot open {video_path}")
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            yield cv2.resize(frame, (W, H), interpolation=cv2.INTER_AREA), fps
    finally:
        cap.release()


def argmax_heatmap(hm: np.ndarray) -> tuple[float, float, float, bool]:
    """Return (x_norm, y_norm, conf, visible) from a HxW heatmap."""
    conf = float(hm.max())
    if conf < HEATMAP_THRESH:
        return 0.0, 0.0, conf, False
    idx = int(hm.argmax())
    y, x = divmod(idx, hm.shape[1])
    return x / float(W), y / float(H), conf, True


def detect_rallies(detections: list[dict], fps: float) -> list[dict]:
    """Group detections into rally segments."""
    rallies: list[dict] = []
    cur: list[dict] = []
    last_vis_f: int | None = None

    def flush():
        if not cur:
            return
        dur = (cur[-1]["f"] - cur[0]["f"]) / fps
        if dur >= MIN_RALLY_S:
            rallies.append({
                "rally_id": len(rallies),
                "start_frame": cur[0]["f"],
                "end_frame": cur[-1]["f"],
                "trajectory": list(cur),
            })

    for d in detections:
        if not d["vis"]:
            continue
        if last_vis_f is None:
            cur = [d]
        else:
            gap_s = (d["f"] - last_vis_f) / fps
            if gap_s > GAP_BOUNDARY_S:
                flush()
                cur = [d]
            else:
                # within same rally (even if small gap; we still only record visible frames)
                cur.append(d)
        last_vis_f = d["f"]
    flush()
    return rallies


@torch.no_grad()
def process_video(video_path: Path, out_dir: Path, orientation: str | None = None) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    vid = video_path.stem

    # Resolve camera orientation: explicit arg > sidecar > side_on (ADR-0001).
    if orientation is None:
        orientation = resolve_orientation(vid, sidecar=load_orientation_map())
    elif orientation not in VALID_ORIENTATIONS:
        raise ValueError(f"invalid orientation {orientation!r}; expected one of {VALID_ORIENTATIONS}")

    model = load_tracknet()
    dev = _device()
    print(f"[extract] {vid}: device={dev}", flush=True)

    # Pull all frames first (resized). For long videos this is RAM-heavy but simplest.
    # For the smoke test this is fine; production should stream.
    frames: list[np.ndarray] = []
    fps: float = 30.0
    for f, src_fps in iter_frames(video_path):
        frames.append(f)
        fps = src_fps
    n = len(frames)
    if n < SEQ_LEN:
        print(f"[extract] {vid}: only {n} frames (<{SEQ_LEN}); skipping")
        return {"video": vid, "fps": fps, "orientation": orientation, "rallies": []}
    print(f"[extract] {vid}: {n} frames @ {fps:.2f} fps", flush=True)

    # Rolling median background over 5s window. Pre-compute one global median
    # for simplicity (5s rolling would 10x runtime); fine for smoke test.
    sample_idx = np.linspace(0, n - 1, num=min(60, n)).astype(int)
    bg = np.median(np.stack([frames[i] for i in sample_idx], axis=0), axis=0).astype(np.float32) / 255.0
    bg_chw = np.transpose(bg, (2, 0, 1))  # (3, H, W)

    detections: list[dict] = []
    t0 = time.time()
    stride = SEQ_LEN  # non-overlapping windows
    for start in range(0, n - SEQ_LEN + 1, stride):
        window = frames[start:start + SEQ_LEN]
        arr = np.stack(window, axis=0).astype(np.float32) / 255.0  # (8, H, W, 3)
        arr = np.transpose(arr, (0, 3, 1, 2)).reshape(SEQ_LEN * 3, H, W)  # (24, H, W)
        x = np.concatenate([arr, bg_chw], axis=0)[None, ...]  # (1, 27, H, W)
        t = torch.from_numpy(x).to(dev)
        out = model(t).cpu().numpy()[0]  # (8, H, W)
        for k in range(SEQ_LEN):
            xn, yn, conf, vis = argmax_heatmap(out[k])
            detections.append({
                "f": start + k,
                "x": round(xn, 4),
                "y": round(yn, 4),
                "conf": round(conf, 4),
                "vis": vis,
            })
    dt = time.time() - t0
    n_vis = sum(1 for d in detections if d["vis"])
    print(f"[extract] {vid}: inference {dt:.1f}s, {n_vis}/{len(detections)} visible", flush=True)

    rallies = detect_rallies(detections, fps)
    print(f"[extract] {vid}: {len(rallies)} rallies (min {MIN_RALLY_S}s)", flush=True)

    payload = {"video": vid, "fps": float(fps), "orientation": orientation, "rallies": rallies}
    out_path = out_dir / f"{vid}.json"
    out_path.write_text(json.dumps(payload, indent=2))
    print(f"[extract] {vid}: wrote {out_path}")
    return payload


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("video", type=Path)
    ap.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    ap.add_argument("--orientation", choices=list(VALID_ORIENTATIONS), default=None,
                    help="camera orientation (default: orientation.json sidecar, else side_on)")
    args = ap.parse_args()
    if not args.video.exists():
        print(f"[extract] missing video: {args.video}", file=sys.stderr)
        return 2
    process_video(args.video, args.out_dir, orientation=args.orientation)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
