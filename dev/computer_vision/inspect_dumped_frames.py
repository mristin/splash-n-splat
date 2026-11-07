#!/usr/bin/env python3

"""
Inspect the frames dumped by the vision smoke test.

The smoke test (see README.md) writes the frames which the models saw, together
with what the C# pipeline found, when started with ``--dump=<dir>``:

    $GODOT --path . scenes/tests/vision_smoke/vision_smoke.tscn -- --seconds=30 --dump=/tmp/frames

This script runs the reference Python decoding of YOLOX on the same frames,
compares it with the C# result, classifies the hand crops in all the rotations,
and renders a contact sheet so that you can see where the pipeline fails.
"""

import argparse
import pathlib
import sys
from typing import Any, List, Tuple

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageDraw

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

# pylint: disable=wrong-import-position
from dataset_schema import FrameMeta, read_model  # noqa: E402

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
YOLOX = REPO_ROOT / "scenes/hand_tracker/yolox/model/yolox_n_body_head_hand_Nx3xHxW.onnx"
GESTURE = REPO_ROOT / "scenes/hand_tracker/gesture/model/rock_paper_scissors_float32.onnx"
LABELS = ["rock", "paper", "scissor", "unknown"]


def detect_hands(
    session: ort.InferenceSession, image: Image.Image, width: int, height: int, threshold: float
) -> List[Tuple[List[float], float]]:
    """Run YOLOX with the reference letterbox and decoding; return the hand boxes."""
    rgb = np.asarray(image.convert("RGB"))
    h, w = rgb.shape[:2]
    ratio = min(width / w, height / h)
    resized = np.asarray(
        Image.fromarray(rgb).resize((int(w * ratio), int(h * ratio)), Image.BILINEAR)
    )
    padded = np.full((height, width, 3), 114, np.uint8)
    padded[: resized.shape[0], : resized.shape[1]] = resized
    x = padded[:, :, ::-1].transpose(2, 0, 1)[None].astype(np.float32)
    out = session.run(None, {"input": x})[0][0]

    grids, strides = [], []
    for stride in (8, 16, 32):
        gh, gw = height // stride, width // stride
        yv, xv = np.meshgrid(np.arange(gh), np.arange(gw), indexing="ij")
        grids.append(np.stack([xv, yv], -1).reshape(-1, 2))
        strides.append(np.full((gh * gw, 1), stride))
    grid = np.concatenate(grids)
    stride = np.concatenate(strides)

    xy = (out[:, :2] + grid) * stride
    wh = np.exp(out[:, 2:4]) * stride
    scores = out[:, 4] * out[:, 7]
    boxes = np.concatenate([xy - wh / 2, xy + wh / 2], 1) / ratio

    order = np.argsort(-scores)
    kept: List[Tuple[List[float], float]] = []
    for i in order:
        if scores[i] < threshold:
            break
        box = boxes[i]
        if all(iou(box, other) <= 0.45 for other, _ in kept):
            kept.append((box.tolist(), float(scores[i])))
    return kept


def iou(a: Any, b: Any) -> float:
    """Compute the intersection over union of two boxes."""
    x1, y1 = max(a[0], b[0]), max(a[1], b[1])
    x2, y2 = min(a[2], b[2]), min(a[3], b[3])
    inter = max(0.0, x2 - x1) * max(0.0, y2 - y1)
    union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / union if union > 0 else 0.0


def crop_input(image: Image.Image, box: List[float], scale: float) -> np.ndarray:
    """Cut the square crop around the box like the game, as a standardized 84x84 array."""
    cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
    side = max(box[2] - box[0], box[3] - box[1]) * scale
    side = min(side, image.width, image.height)
    x1 = min(max(cx - side / 2, 0), image.width - side)
    y1 = min(max(cy - side / 2, 0), image.height - side)
    crop = image.convert("L").crop((int(x1), int(y1), int(x1 + side), int(y1 + side)))
    x = np.asarray(crop.resize((84, 84), Image.BILINEAR), np.float32)
    return (x - x.mean()) / (x.std() + 1e-6)


def main() -> int:
    """Execute the entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dump_dir", help="Directory written by the smoke test with --dump")
    parser.add_argument("--out", help="Where to write the contact sheet", default=None)
    parser.add_argument("--crop-scale", type=float, default=1.5)
    parser.add_argument("--threshold", type=float, default=0.3)
    args = parser.parse_args()

    dump_dir = pathlib.Path(args.dump_dir)
    frames = sorted(dump_dir.glob("frame_*.png"))
    if not frames:
        print(f"No frames in {dump_dir}", file=sys.stderr)
        return 1

    detector = ort.InferenceSession(str(YOLOX), providers=["CPUExecutionProvider"])
    classifier = ort.InferenceSession(str(GESTURE), providers=["CPUExecutionProvider"])

    tiles = []
    agreements = []
    for path in frames:
        image = Image.open(path).convert("RGB")
        meta = read_model(path.with_suffix(".json"), FrameMeta)
        level = (meta.level or "320x256").split(" ")[0]
        width, height = (int(v) for v in level.split("x"))

        reference = detect_hands(detector, image, width, height, args.threshold)
        reference_hi = detect_hands(detector, image, 640, 480, args.threshold)
        csharp = [(h.box, h.score) for h in meta.hands]

        matched = sum(1 for box, _ in reference if any(iou(box, b) > 0.5 for b, _ in csharp))
        agreements.append((len(reference), len(csharp), matched))

        draw = ImageDraw.Draw(image)
        for box, score in reference_hi:
            draw.rectangle(box, outline=(80, 160, 255), width=1)
        for box, score in reference:
            draw.rectangle(box, outline=(255, 60, 60), width=3)
        lines = []
        for hand in meta.hands:
            box = hand.box
            draw.rectangle(box, outline=(60, 255, 90), width=2)
            sample = crop_input(image, box, args.crop_scale)
            batch = np.stack([np.rot90(sample, -k) for k in (0, 1, 3)])[:, :, :, None]
            p = classifier.run(None, {"input": batch.astype(np.float32)})[0]
            per_rotation = " | ".join(
                LABELS[int(np.argmax(row))] + f" {np.max(row):.2f}" for row in p
            )
            lines.append(
                f"#{hand.id} C#: {hand.gesture} o{hand.open or 0:.2f} f{hand.fist or 0:.2f}; "
                f"py rot 0/90/270: {per_rotation}"
            )
            thumb = Image.fromarray(np.clip(sample * 50 + 128, 0, 255).astype(np.uint8)).convert(
                "RGB"
            )
            image.paste(thumb.resize((84, 84)), (int(max(0, box[0])), int(min(396, box[3] + 2))))
        draw.text(
            (4, 4),
            f"{path.name} {level}: py {len(reference)} / C# {len(csharp)}",
            fill=(255, 255, 0),
        )
        for i, line in enumerate(lines):
            draw.text((4, 18 + 12 * i), line, fill=(255, 255, 0))
        print(
            f"{path.name}: python {len(reference)} (640x480: {len(reference_hi)}), C# {len(csharp)}; "
            + "; ".join(lines)
        )
        tiles.append(image)

    columns = 4
    rows = (len(tiles) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * 320, rows * 240))
    for i, tile in enumerate(tiles):
        sheet.paste(tile.resize((320, 240)), ((i % columns) * 320, (i // columns) * 240))
    out = pathlib.Path(args.out) if args.out else dump_dir / "contact_sheet.png"
    sheet.save(out)
    total_ref = sum(a for a, _, _ in agreements)
    total_matched = sum(m for _, _, m in agreements)
    print(f"Python detections matched by C#: {total_matched}/{total_ref}")
    print(f"Wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
