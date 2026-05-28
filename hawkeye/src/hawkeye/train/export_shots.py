"""Export per-rally TRAINING records (shots.jsonl) with provenance + corroboration.

Implements the TRAINING-EXPORT-SCHEMA + the label-quality rule:
  - Only HUMAN labels are training-grade (`split=train`). The classifier (System 2)
    and the heuristic auto_annotate are NOT independent (System 2 was trained on the
    heuristic's labels), so their AGREEMENT is circular and must NOT be promoted to
    "corroborated". System-2-only rows go to `holdout` (eval, never trained); cv-vs-
    heuristic DISAGREEMENT is `quarantine` (kept for review, never trained).
  - Every record stores clip_ref + landing COORDINATE (never bare in/out) + full
    provenance (source/confidence/corroboration + per-signal votes).

This is the data flywheel: human overrides accumulate as the only trustworthy
training labels, breaking System 2's heuristic-lineage dependency over time.

Usage:
    python -m hawkeye.train.export_shots                 # emit shots.jsonl (no model = cv vote null)
    python -m hawkeye.train.export_shots --with-cv       # run the classifier for cv votes (slower)
    python -m hawkeye.train.export_shots --self-test     # unit-test the corroboration logic
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Optional

REPO_ROOT = Path(__file__).resolve().parents[3]
TRAJ_DIR = REPO_ROOT / "data" / "processed" / "trajectories"
VIDEO_DIR = REPO_ROOT / "data" / "raw" / "youtube"
HEURISTIC_ANN = REPO_ROOT / "data" / "processed" / "annotations_heuristic_v1.jsonl"
HUMAN_ANN = REPO_ROOT / "data" / "processed" / "annotations.jsonl"
HUMAN_HOLDOUT = REPO_ROOT / "data" / "processed" / "annotations_human_holdout.jsonl"
OUT_PATH = REPO_ROOT / "data" / "training" / "shots.jsonl"
SCHEMA_VERSION = "0.1"


def decide(human: Optional[str], cv: Optional[str], heuristic: Optional[str]) -> dict:
    """Pure corroboration logic → {source, corroboration, split_hint, human_corrected}.

    The crux: cv (System 2) and heuristic share lineage → their agreement is NOT
    independent corroboration. Only a human label is training-grade.
    """
    if human is not None:
        # Human is authoritative + independent → training-grade.
        corrected = cv is not None and cv != human
        return {"source": "human", "corroboration": "corroborated",
                "split_hint": "train", "human_corrected": corrected}
    if cv is not None and heuristic is not None:
        if cv == heuristic:
            # Agreement, but correlated signals → eval-only, never trained.
            return {"source": "cvPipeline", "corroboration": "singleSignal",
                    "split_hint": "holdout", "human_corrected": False}
        # Disagreement → quarantine for review (kept, not trained).
        return {"source": "cvPipeline", "corroboration": "conflict",
                "split_hint": "quarantine", "human_corrected": False}
    if cv is not None or heuristic is not None:
        return {"source": "cvPipeline", "corroboration": "singleSignal",
                "split_hint": "holdout", "human_corrected": False}
    return {"source": "cvPipeline", "corroboration": "unverified",
            "split_hint": "quarantine", "human_corrected": False}


def _heuristic_winner(trajectory: list[dict]) -> Optional[str]:
    vis = [p for p in trajectory if p.get("vis", True)]
    if len(vis) < 3:
        return None
    last = vis[-5:]
    mean_x = sum(float(p["x"]) for p in last) / len(last)
    return "sideA" if mean_x < 0.5 else "sideB"


def _is_not_rally(rec: dict) -> bool:
    """Non-play row marked by the labeler's N key (warm-up/junk)."""
    return (rec.get("not_rally") is True
            or rec.get("winner") == "not_rally"
            or rec.get("split") == "not_rally")


def _load_labels(path: Path) -> dict[tuple[str, int], str]:
    out: dict[tuple[str, int], str] = {}
    if not path.exists():
        return out
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except Exception:
            continue
        if _is_not_rally(rec):
            continue  # EXCLUDE: never a sideA/sideB winner (segregated split)
        if rec.get("winner") in ("sideA", "sideB"):
            out[(rec["video"], int(rec["rally_id"]))] = rec["winner"]
    return out


def _load_not_rally(path: Path) -> set[tuple[str, int]]:
    """Segregated not_rally rows kept for a future rally-vs-not-rally filter."""
    out: set[tuple[str, int]] = set()
    if not path.exists():
        return out
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except Exception:
            continue
        if _is_not_rally(rec):
            out.add((rec["video"], int(rec["rally_id"])))
    return out


def build_record(vid: str, rally: dict, fps: float, *, human, cv, heuristic) -> dict:
    d = decide(human, cv, heuristic)
    label_value = human or cv or heuristic
    sf, ef = rally.get("start_frame"), rally.get("end_frame")
    return {
        "schema_version": SCHEMA_VERSION,
        "shot_id": f"{vid}:r{rally['rally_id']}",
        "clip_ref": {
            "video_id": vid,
            "file": str((VIDEO_DIR / f"{vid}.mp4")),
            "fps": fps,
            "start_frame": sf, "end_frame": ef,
        },
        "label": {"task": "rally_winner", "value": label_value, "landing": None},
        "provenance": {
            "source": d["source"],
            "confidence": 1.0 if d["source"] == "human" else None,
            "corroboration": d["corroboration"],
            "human_corrected": d["human_corrected"],
            "signals": {
                "cv_pipeline": ({"value": cv} if cv else None),
                "heuristic": ({"value": heuristic} if heuristic else None),
                "human": ({"value": human} if human else None),
            },
        },
        "split_hint": d["split_hint"],
    }


def load_trainable(path: Path = OUT_PATH) -> list[dict]:
    """Loader for retrain: yields ONLY training-grade rows (split_hint == 'train')."""
    rows = []
    if not path.exists():
        return rows
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        rec = json.loads(line)
        if rec.get("split_hint") == "train":
            rows.append(rec)
    return rows


def _split_from_result(source: str, corroboration: str) -> str:
    """Mirror decide()'s split rule for an already-assembled on-device RallyResult."""
    if source == "human":
        return "train"
    if corroboration == "conflict":
        return "quarantine"
    if corroboration == "corroborated":   # ≥2 INDEPENDENT signals agreed (future: next-serve oracle)
        return "train"
    return "holdout"                      # singleSignal / unverified → eval only


def ingest_ondevice(jsonl_dir: Path, out_path: Path = OUT_PATH) -> int:
    """Ingest the app's on-device RallyResult JSONL files → shots.jsonl training records.

    The app writes each FINALIZED RallyResult (Codable) as one JSON line to
    Application Support/TrainingExport/<matchUUID>.jsonl (incl. human overrides).
    Corroboration/training-grade is decided HERE, not on-device — the app just
    encodes the rich RallyResult it already has. Latest line per (match, rallyIndex)
    wins (a human override supersedes the earlier auto entry).
    """
    files = sorted(Path(jsonl_dir).glob("*.jsonl"))
    if not files:
        print(f"[ingest] no on-device JSONL under {jsonl_dir}"); return 2
    from collections import Counter
    split_counts = Counter(); n = 0
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("a") as out:
        for fp in files:
            match_id = fp.stem
            latest: dict[int, dict] = {}
            for line in fp.read_text().splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    rr = json.loads(line)
                except Exception:
                    continue
                latest[int(rr["rallyIndex"])] = rr   # latest wins (override supersedes)
            for ridx, rr in sorted(latest.items()):
                source = rr.get("source", "cvPipeline")
                corr = rr.get("corroboration", "singleSignal")
                cv = (rr.get("cvVote") or {}).get("side")
                human = rr["winner"] if source == "human" else None
                rec = {
                    "schema_version": SCHEMA_VERSION,
                    "shot_id": f"{match_id}:r{ridx}",
                    "clip_ref": rr.get("clipRef"),   # on-device {fileName,startTime,endTime}
                    "label": {"task": "rally_winner", "value": rr["winner"],
                              "landing": rr.get("landing")},
                    "provenance": {
                        "source": source,
                        "confidence": rr.get("confidence"),
                        "corroboration": corr,
                        "human_corrected": bool(human and cv and cv != human),
                        "signals": {
                            "cv_pipeline": ({"value": cv} if cv else None),
                            "heuristic": None,
                            "human": ({"value": human} if human else None),
                        },
                    },
                    "split_hint": _split_from_result(source, corr),
                    "origin": "on-device",
                }
                out.write(json.dumps(rec) + "\n")
                split_counts[rec["split_hint"]] += 1; n += 1
    print(f"[ingest] appended {n} on-device records → {out_path}")
    print(f"[ingest] split breakdown: {dict(split_counts)} (human overrides → train; cv-only → holdout)")
    return 0


def _not_rally_record(vid: str, rally: dict, fps: float) -> dict:
    """A stored-but-segregated record for non-play footage (labeler's N key).

    split_hint='not_rally' keeps it OUT of train/holdout/quarantine while
    preserving it as future rally-vs-not-rally filter data.
    """
    sf, ef = rally.get("start_frame"), rally.get("end_frame")
    return {
        "schema_version": SCHEMA_VERSION,
        "shot_id": f"{vid}:r{rally['rally_id']}",
        "clip_ref": {
            "video_id": vid,
            "file": str((VIDEO_DIR / f"{vid}.mp4")),
            "fps": fps,
            "start_frame": sf, "end_frame": ef,
        },
        "label": {"task": "rally_winner", "value": None, "landing": None},
        "not_rally": True,
        "provenance": {
            "source": "human", "confidence": 1.0,
            "corroboration": "not_rally", "human_corrected": False,
            "signals": {"cv_pipeline": None, "heuristic": None,
                        "human": {"value": "not_rally"}},
        },
        "split_hint": "not_rally",
    }


def run(with_cv: bool) -> int:
    human = {**_load_labels(HUMAN_ANN), **_load_labels(HUMAN_HOLDOUT)}
    heuristic = _load_labels(HEURISTIC_ANN)
    not_rally = (_load_not_rally(HUMAN_ANN) | _load_not_rally(HUMAN_HOLDOUT)
                 | _load_not_rally(HEURISTIC_ANN))
    model = None
    featurize = None
    if with_cv:
        import numpy as np  # noqa
        import coremltools as ct
        from .winner_classifier import featurize as _f, FEATURE_DIM  # noqa
        featurize = _f
        mp = REPO_ROOT / "data" / "processed" / "RallyWinnerClassifier.mlpackage"
        model = ct.models.MLModel(str(mp)) if mp.exists() else None

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    from collections import Counter
    split_counts = Counter()
    n = 0
    with OUT_PATH.open("w") as out:
        for jp in sorted(TRAJ_DIR.glob("*.json")):
            data = json.loads(jp.read_text())
            vid = data["video"]; fps = float(data.get("fps", 30.0))
            for rally in data.get("rallies", []):
                rid = int(rally["rally_id"])
                traj = rally["trajectory"]
                # Non-play footage: emit a segregated record (never a winner),
                # do not run cv/heuristic on it.
                if (vid, rid) in not_rally:
                    rec = _not_rally_record(vid, rally, fps)
                    out.write(json.dumps(rec) + "\n")
                    split_counts[rec["split_hint"]] += 1
                    n += 1
                    continue
                h = human.get((vid, rid))
                heur = heuristic.get((vid, rid)) or _heuristic_winner(traj)
                cv = None
                if model is not None and featurize is not None:
                    import numpy as np
                    feats = featurize(traj).astype(np.float32).reshape(1, -1)
                    logits = np.asarray(next(iter(model.predict(
                        {"trajectory_features": feats}).values()))).reshape(-1)
                    cv = "sideA" if int(np.argmax(logits)) == 0 else "sideB"
                rec = build_record(vid, rally, fps, human=h, cv=cv, heuristic=heur)
                out.write(json.dumps(rec) + "\n")
                split_counts[rec["split_hint"]] += 1
                n += 1
    print(f"[export] wrote {n} records → {OUT_PATH}")
    print(f"[export] split breakdown: {dict(split_counts)}")
    print(f"[export] trainable (split=train): {split_counts['train']} "
          f"(only human labels are training-grade by design)")
    print(f"[export] not_rally (segregated, never trained/evaled): "
          f"{split_counts['not_rally']}")
    return 0


def _self_test() -> int:
    cases = [
        # (human, cv, heuristic) -> expected (source, corroboration, split, corrected)
        (("sideA", "sideA", "sideA"), ("human", "corroborated", "train", False)),
        (("sideA", "sideB", "sideA"), ("human", "corroborated", "train", True)),   # human corrected cv
        ((None, "sideA", "sideA"),    ("cvPipeline", "singleSignal", "holdout", False)),  # correlated agreement ≠ corroborated
        ((None, "sideA", "sideB"),    ("cvPipeline", "conflict", "quarantine", False)),
        ((None, "sideA", None),       ("cvPipeline", "singleSignal", "holdout", False)),
        ((None, None, None),          ("cvPipeline", "unverified", "quarantine", False)),
    ]
    ok = True
    for (h, cv, heur), (es, ec, esp, ecorr) in cases:
        d = decide(h, cv, heur)
        got = (d["source"], d["corroboration"], d["split_hint"], d["human_corrected"])
        passed = got == (es, ec, esp, ecorr)
        ok = ok and passed
        print(f"  decide(h={h},cv={cv},heur={heur}) -> {got}  {'PASS' if passed else 'FAIL exp '+str((es,ec,esp,ecorr))}")
    print("SELF-TEST", "PASS" if ok else "FAIL")
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--with-cv", action="store_true", help="run the classifier for cv votes (slower)")
    ap.add_argument("--self-test", action="store_true", help="unit-test the corroboration logic and exit")
    ap.add_argument("--ingest-ondevice", metavar="DIR",
                    help="ingest the app's on-device RallyResult JSONL files → shots.jsonl")
    args = ap.parse_args()
    if args.self_test:
        return _self_test()
    if args.ingest_ondevice:
        return ingest_ondevice(Path(args.ingest_ondevice))
    return run(args.with_cv)


if __name__ == "__main__":
    raise SystemExit(main())
