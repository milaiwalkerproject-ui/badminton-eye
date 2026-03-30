# Badminton Eye - Shuttle Detection Training Pipeline

## Overview

This pipeline trains a YOLOv11 nano model for real-time shuttlecock detection in badminton match footage. The trained model is exported as CoreML (`.mlmodel`) for on-device inference on Apple Neural Engine, powering Badminton Eye's shuttle tracking feature.

**Model**: YOLOv11 nano (~3.2M parameters) -- optimized for mobile inference speed
**Export**: CoreML with NMS (Non-Maximum Suppression) baked in
**Target**: mAP50 > 0.7 for production use

## Prerequisites

- **Python 3.10+** (3.11 recommended)
- **pip** (package manager)
- **GPU recommended**:
  - NVIDIA GPU with CUDA support (Linux/Windows)
  - Apple Silicon with MPS backend (macOS)
  - CPU training works but is significantly slower

## Setup

```bash
cd scripts/training
pip install -r requirements.txt
```

This installs:
- `ultralytics` -- YOLO model training and export framework
- `coremltools` -- Apple CoreML model conversion
- `torch` -- PyTorch deep learning backend

## Dataset Requirements

Prepare an annotated dataset before training. See [ANNOTATION_GUIDE.md](ANNOTATION_GUIDE.md) for detailed labeling instructions.

### Minimum Requirements

- **2,000 annotated images** minimum (3,000+ recommended)
- **YOLO format** bounding box annotations (see annotation guide)
- **70/30 train/val split**

### Diversity Requirements

The dataset must include variety across these dimensions for robust real-world detection:

| Dimension | Requirements |
|-----------|-------------|
| **Courts** | Indoor wooden, outdoor concrete, various floor colors |
| **Lighting** | Natural daylight, fluorescent, mixed, shadows |
| **Camera angles** | Side-court, behind-court, elevated/broadcast |
| **Game states** | Rally exchanges, serves, clears, smashes, drops |
| **Motion blur** | At least 20% of frames must contain motion-blurred shuttles |

### Dataset Structure

```
dataset/
  images/
    train/    # ~70% of images
    val/      # ~30% of images
  labels/
    train/    # Corresponding YOLO .txt annotations
    val/
  dataset.yaml
```

Example `dataset.yaml`:

```yaml
path: ./dataset
train: images/train
val: images/val
names:
  0: shuttlecock
```

## Training

### Basic Training

```bash
python train.py --data path/to/dataset.yaml --epochs 100 --imgsz 640
```

### Full Argument Reference

| Argument | Default | Description |
|----------|---------|-------------|
| `--data` | (required) | Path to YOLO-format `dataset.yaml` |
| `--epochs` | 100 | Number of training epochs |
| `--imgsz` | 640 | Input image size in pixels |
| `--batch` | 16 | Batch size (reduce if running out of memory) |
| `--output` | `runs/shuttle_detect` | Output project directory |
| `--model` | `yolo11n.pt` | Base YOLO model (nano weights) |
| `--name` | `shuttle_v1` | Run name for this training session |

### Example Commands

```bash
# Standard training
python train.py --data ./dataset/dataset.yaml --epochs 100

# Longer training with smaller batch (for limited GPU memory)
python train.py --data ./dataset/dataset.yaml --epochs 200 --batch 8

# Custom output directory
python train.py --data ./dataset/dataset.yaml --output ./my_runs --name experiment_1
```

**Note:** The first run automatically downloads `yolo11n.pt` base weights (~6 MB) from Ultralytics servers.

## Expected Output

After training completes, the script:

1. **Prints validation metrics** (mAP50 and mAP50-95)
2. **Exports a CoreML model** with NMS baked in
3. **Shows the export path** to the `.mlmodel` file

### Output Directory Structure

```
runs/shuttle_detect/shuttle_v1/
  weights/
    best.pt          # Best checkpoint (highest mAP)
    last.pt          # Final epoch checkpoint
  results.csv        # Training metrics per epoch
  ...
```

The exported `.mlmodel` file appears alongside the weights directory.

### Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| mAP50 | > 0.7 | Minimum for production use |
| mAP50 | > 0.85 | Good quality detection |
| mAP50-95 | > 0.5 | Strong across IoU thresholds |

If mAP50 falls below 0.7, the script prints a warning with improvement suggestions.

## Integration

After training and validating the model:

1. **Copy the `.mlmodel` file** into `BadmintonEye/BadmintonEye/Models/`
2. **Add to Xcode project**: drag the `.mlmodel` file into the Xcode project navigator
3. **Create `CoreMLShuttleDetector`**: implement a class conforming to the `ShuttleDetecting` protocol that wraps the CoreML model for inference (Phase 9)
4. **Replace placeholder**: swap out the existing `generatePlaceholderPositions()` in `HawkEyePipeline` with real model detections

The `ShuttleDetecting` protocol abstracts the detection interface so the app works with both the placeholder and real CoreML model.

## Troubleshooting

### CUDA Out of Memory

```
RuntimeError: CUDA out of memory
```

Reduce batch size: `--batch 8` or `--batch 4`. If still failing, reduce image size: `--imgsz 416`.

### MPS Backend Issues (Apple Silicon)

If training on Apple Silicon encounters MPS errors, set the environment variable:

```bash
export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
python train.py --data ./dataset/dataset.yaml
```

### Low mAP After Training

If mAP50 is below 0.7:

1. **Check annotation quality** -- spot-check labels using CVAT/Label Studio visualization
2. **Increase dataset diversity** -- more courts, lighting, angles
3. **Add motion blur examples** -- ensure >= 20% of dataset has blur
4. **Train longer** -- try `--epochs 200` or `--epochs 300`
5. **Verify label format** -- ensure normalized coordinates, class_id = 0

### Model Does Not Download

If `yolo11n.pt` fails to download, manually download from the [Ultralytics releases](https://github.com/ultralytics/assets/releases) and place in the training directory.

### CoreML Export Fails

Ensure `coremltools>=7.0` is installed:

```bash
pip install --upgrade coremltools
```
