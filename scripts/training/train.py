#!/usr/bin/env python3
"""
Badminton Eye - Shuttlecock Detection Training Script

Trains a YOLOv11 nano model on annotated badminton footage and exports
it as a CoreML model (.mlmodel) with NMS baked in for on-device inference
on Apple Neural Engine.

Usage:
    python train.py --data path/to/dataset.yaml --epochs 100 --imgsz 640

The exported .mlmodel should be copied into the Xcode project at
BadmintonEye/BadmintonEye/Models/ for integration with the
ShuttleDetecting protocol (Phase 9).
"""

import argparse
import sys
from pathlib import Path

from ultralytics import YOLO


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments for training configuration."""
    parser = argparse.ArgumentParser(
        description="Train YOLO nano for shuttlecock detection and export to CoreML"
    )
    parser.add_argument(
        "--data",
        type=str,
        required=True,
        help="Path to YOLO-format dataset.yaml",
    )
    parser.add_argument(
        "--epochs",
        type=int,
        default=100,
        help="Number of training epochs (default: 100)",
    )
    parser.add_argument(
        "--imgsz",
        type=int,
        default=640,
        help="Input image size in pixels (default: 640)",
    )
    parser.add_argument(
        "--batch",
        type=int,
        default=16,
        help="Batch size (default: 16)",
    )
    parser.add_argument(
        "--output",
        type=str,
        default="runs/shuttle_detect",
        help="Output project directory (default: runs/shuttle_detect)",
    )
    parser.add_argument(
        "--model",
        type=str,
        default="yolo11n.pt",
        help="Base YOLO model weights (default: yolo11n.pt)",
    )
    parser.add_argument(
        "--name",
        type=str,
        default="shuttle_v1",
        help="Run name for this training session (default: shuttle_v1)",
    )
    return parser.parse_args()


def print_banner(args: argparse.Namespace) -> None:
    """Print a configuration summary banner."""
    print("=" * 60)
    print("  Badminton Eye - Shuttlecock Detection Training")
    print("=" * 60)
    print(f"  Base model:   {args.model}")
    print(f"  Dataset:      {args.data}")
    print(f"  Epochs:       {args.epochs}")
    print(f"  Image size:   {args.imgsz}")
    print(f"  Batch size:   {args.batch}")
    print(f"  Output dir:   {args.output}/{args.name}")
    print("=" * 60)
    print()


def main() -> None:
    """Train YOLO nano model and export to CoreML."""
    args = parse_args()
    print_banner(args)

    # Validate dataset path
    data_path = Path(args.data)
    if not data_path.exists():
        print(f"ERROR: Dataset config not found: {args.data}")
        sys.exit(1)

    # Load base model
    print(f"[1/4] Loading base model: {args.model}")
    model = YOLO(args.model)

    # Train
    print(f"[2/4] Starting training for {args.epochs} epochs...")
    model.train(
        data=args.data,
        epochs=args.epochs,
        imgsz=args.imgsz,
        batch=args.batch,
        project=args.output,
        name=args.name,
        exist_ok=True,
    )

    # Validate
    print("[3/4] Running validation...")
    metrics = model.val()
    map50 = metrics.box.map50
    map50_95 = metrics.box.map
    print(f"  mAP50:    {map50:.4f}")
    print(f"  mAP50-95: {map50_95:.4f}")
    print()

    if map50 < 0.7:
        print("WARNING: mAP50 below 0.7 target. Consider improving dataset quality.")
        print("  - Check annotation consistency (see ANNOTATION_GUIDE.md)")
        print("  - Ensure sufficient motion blur examples (>=20% of dataset)")
        print("  - Add more diverse court/lighting conditions")
        print()

    # Export to CoreML with NMS
    print("[4/4] Exporting to CoreML with NMS...")
    export_path = model.export(format="coreml", nms=True)
    print(f"  Exported model: {export_path}")
    print()

    # Integration reminder
    print("=" * 60)
    print("  NEXT STEPS")
    print("=" * 60)
    print("  Copy the .mlmodel file into")
    print("  BadmintonEye/BadmintonEye/Models/ and add to Xcode project.")
    print("  Then create a CoreMLShuttleDetector conforming to the")
    print("  ShuttleDetecting protocol (Phase 9).")
    print("=" * 60)


if __name__ == "__main__":
    main()
