# Shuttlecock Annotation Guide

## Overview

This guide describes how to annotate shuttlecocks in badminton match footage for training a YOLO nano object detection model. The trained model powers Badminton Eye's on-device shuttle tracking, enabling real-time trajectory analysis during matches.

We annotate bounding boxes around the shuttlecock in individual video frames. The model learns to detect the shuttle across diverse court environments, lighting conditions, and motion states (including motion blur from high-speed rallies).

## Tool Setup

### Recommended Annotation Tools

Use a free, open-source annotation tool that supports YOLO format export:

- **CVAT** (Computer Vision Annotation Tool) -- https://www.cvat.ai
- **Label Studio** -- https://labelstud.io

Both tools support YOLO-format export and offer efficient bounding box annotation workflows.

### YOLO Label Format

Each image has a corresponding `.txt` label file. Each line represents one annotation:

```
class_id center_x center_y width height
```

All values are normalized to 0-1 relative to image dimensions:

- `class_id`: integer class index (0 for shuttlecock)
- `center_x`: bounding box center X / image width
- `center_y`: bounding box center Y / image height
- `width`: bounding box width / image width
- `height`: bounding box height / image height

Example for a shuttlecock at the center-right of a 1920x1080 image:

```
0 0.75 0.45 0.02 0.04
```

## Labeling Rules

### Class Definition

- **Single class**: `shuttlecock` (class_id = 0)
- There is only one shuttlecock in play during a badminton match
- Annotate **one bounding box per shuttlecock per frame**

### Bounding Box Placement

1. The bounding box should **tightly enclose the entire shuttlecock**, including the feathers (skirt) and cork (head)
2. Do not add excessive padding beyond the visible shuttle outline
3. For **motion blur**: draw the box around the **full blur streak**, not just the cork. The elongated blur trail is the shuttle's visible footprint and must be captured
4. If the shuttlecock is **partially occluded** (by the net, a player's body, or racket), still annotate the **visible portion** with a tight bounding box
5. **Skip frames** where the shuttlecock is completely invisible (e.g., hidden behind a player, out of frame)

### What NOT to Annotate

- Shuttlecocks on the ground (not in play)
- Shuttlecocks in spectator areas or held by players between points
- Duplicate shuttles visible in tube/container near the court

## Motion Blur Specifics

High-speed shuttlecock travel (up to 400+ km/h in smashes) produces significant motion blur in standard video:

- **Blur elongates the shuttle** along its direction of travel, creating a streak rather than a crisp outline
- The bounding box must capture the **full extent of the blur streak**
- Even when heavily blurred, the shuttle should still be annotated -- the model needs to learn blur patterns
- Motion blur frames are especially important for real-match detection accuracy

### Examples of Blur Annotation

| Scenario | Box Shape | Notes |
|----------|-----------|-------|
| Clear/stationary shuttle | Small, roughly square | Tight around cork + feathers |
| Moderate blur (lift/clear) | Slightly elongated | Box stretches along travel direction |
| Heavy blur (smash) | Long, narrow rectangle | Full streak from leading to trailing edge |
| Serve toss (upward) | Vertically elongated | Blur runs top-to-bottom |

**Rule of thumb:** If you can see any trace of the shuttle, annotate it. The bounding box should contain all visible pixels of the shuttle and its blur trail.

## Dataset Directory Structure

Organize the dataset in YOLO format:

```
dataset/
  images/
    train/
    val/
  labels/
    train/
    val/
  dataset.yaml
```

- `images/train/` and `images/val/` contain the frame images (`.jpg` or `.png`)
- `labels/train/` and `labels/val/` contain the corresponding `.txt` annotation files
- Each label file must have the same name as its image (e.g., `frame_001.jpg` -> `frame_001.txt`)
- An image with no visible shuttlecock should have an **empty** label file (not a missing one)

## dataset.yaml

Create a `dataset.yaml` at the dataset root:

```yaml
path: ./dataset
train: images/train
val: images/val
names:
  0: shuttlecock
```

This file is passed to `train.py --data` and tells YOLO where to find images and labels.

## Quality Checklist

Before starting training, verify the dataset meets these requirements:

- [ ] **Minimum 2,000 annotated images** (3,000+ recommended for production quality)
- [ ] **70/30 train/val split** (approximately 1,400 train / 600 val for 2,000 images)
- [ ] **Diverse courts**: indoor wooden, outdoor concrete, various floor colors, different net types
- [ ] **Diverse lighting**: natural daylight, fluorescent indoor, mixed lighting, shadows
- [ ] **Various camera angles**: side-court, behind-court, elevated/broadcast angle
- [ ] **Rally and serve frames**: both fast exchanges and service motion
- [ ] **Motion blur frames**: at least 20% of the dataset should contain motion-blurred shuttles
- [ ] **Consistent annotation quality**: spot-check 50+ random labels for tight bounding boxes
- [ ] **No missing label files**: every image has a corresponding `.txt` file (empty if no shuttle visible)
- [ ] **Single class only**: all annotations use class_id 0
