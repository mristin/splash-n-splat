#!/usr/bin/env python3

"""
Evaluate the game's hand detector (YOLOX nano) on recorded sessions.

As the reference, we take the hands found by the large YOLOX (medium) which
dev/computer_vision/train_fist_classifier.py cached in the sessions
(``hands.<model>.<threshold>.json``). For several input resolutions and score
thresholds of nano, we report how many reference hands nano finds (recall), how
many of its detections have no reference hand (false positives per frame, e.g.,
elbows), and we save a contact sheet of the false positives to look at.

    venv/bin/python dev/computer_vision/evaluate_detector.py <session> [<session> ...]
"""

import argparse
import pathlib
import sys
from typing import Dict, List, Sequence, Tuple

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageDraw

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

# pylint: disable=wrong-import-position
from dataset_schema import HandCache, read_model  # noqa: E402
from inspect_dumped_frames import YOLOX, detect_hands, iou  # noqa: E402


def load_reference(session: pathlib.Path) -> Dict[str, List[List[float]]]:
    """Load the cached hands of the large detector."""
    caches = sorted(session.glob("hands.yolox_m*.json"))
    if not caches:
        raise RuntimeError(
            f"No cached reference hands in {session}; run train_fist_classifier.py first."
        )
    return read_model(caches[0], HandCache).root


def main() -> int:
    """Execute the entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sessions", nargs="+")
    parser.add_argument("--every", type=int, default=3, help="Use every n-th frame")
    parser.add_argument("--out", default="/tmp/false_positives.png")
    parser.add_argument(
        "--lowest",
        action="store_true",
        help="Show the lowest-scoring false positives (rather than the highest)",
    )
    args = parser.parse_args()

    session = ort.InferenceSession(str(YOLOX), providers=["CPUExecutionProvider"])

    frames: List[Tuple[pathlib.Path, List[List[float]]]] = []
    for directory in args.sessions:
        path = pathlib.Path(directory)
        reference = load_reference(path)
        for name in sorted(reference)[:: args.every]:
            frames.append((path / name, reference[name]))
    print(f"Frames: {len(frames)}, reference hands: {sum(len(r) for _, r in frames)}")

    sizes: Sequence[Tuple[int, int]] = [(160, 128), (256, 192), (320, 256), (416, 320)]
    thresholds = [0.3, 0.4, 0.5, 0.6]
    detections: Dict[Tuple[int, int], List[List[Tuple[List[float], float]]]] = {
        size: [] for size in sizes
    }
    for path, _ in frames:
        image = Image.open(path).convert("RGB")
        for size in sizes:
            detections[size].append(detect_hands(session, image, size[0], size[1], 0.3))

    false_positives: List[Tuple[pathlib.Path, List[float], float]] = []
    print(f"{'input':>8} {'thresh':>6} {'recall':>7} {'FP/frame':>9} {'FP score med':>12}")
    for size in sizes:
        for threshold in thresholds:
            found = 0
            total = 0
            fp_scores: List[float] = []
            for (path, reference), boxes in zip(frames, detections[size]):
                kept = [(box, score) for box, score in boxes if score >= threshold]
                total += len(reference)
                found += sum(1 for r in reference if any(iou(r, b) > 0.3 for b, _ in kept))
                for box, score in kept:
                    if not any(iou(r, box) > 0.3 for r in reference):
                        fp_scores.append(score)
                        if size == (320, 256) and threshold == 0.3:
                            false_positives.append((path, box, score))
            print(
                f"{size[0]}x{size[1]:<4} {threshold:6.2f} {found / max(1, total):7.3f} "
                f"{len(fp_scores) / len(frames):9.3f} "
                f"{np.median(fp_scores) if fp_scores else float('nan'):12.2f}"
            )

    # A contact sheet of the false positives, with some context around them.
    tiles = []
    order = sorted(false_positives, key=lambda f: f[2] if args.lowest else -f[2])
    for path, box, score in order[:48]:
        image = Image.open(path).convert("RGB")
        cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
        side = max(box[2] - box[0], box[3] - box[1]) * 3
        crop = image.crop((cx - side / 2, cy - side / 2, cx + side / 2, cy + side / 2)).resize(
            (160, 160)
        )
        draw = ImageDraw.Draw(crop)
        draw.rectangle((53, 53, 106, 106), outline=(255, 0, 0), width=2)
        draw.text((4, 4), f"{score:.2f}", fill=(255, 255, 0))
        tiles.append(crop)
    if tiles:
        sheet = Image.new("RGB", (8 * 160, ((len(tiles) + 7) // 8) * 160))
        for i, tile in enumerate(tiles):
            sheet.paste(tile, ((i % 8) * 160, (i // 8) * 160))
        sheet.save(args.out)
        print(f"Wrote {len(tiles)} false positives (320x256, >= 0.3) to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
