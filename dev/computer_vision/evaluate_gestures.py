#!/usr/bin/env python3

"""
Evaluate the gesture classification on frames recorded with the guided recording
of the vision smoke test (see README.md):

    $GODOT --path . scenes/tests/vision_smoke/vision_smoke.tscn -- --record --dump=<dir>
    venv/bin/python dev/computer_vision/evaluate_gestures.py <dir>

Each frame is labeled with the gesture the player was asked to show (open, fist
or other). We detect the hands with the reference YOLOX decoding, assume that
every hand in the frame shows the asked gesture, and measure how the classifier
decides for the different crop scales and rotations. The numbers which matter
for the game are:

* open -> OPEN and fist -> FIST: how often a gesture is recognized at all
  (misses only delay a shot);
* open -> FIST: the false shots, which must be as rare as possible.
"""

import argparse
import itertools
import pathlib
import sys
from typing import Dict, List, Sequence

import numpy as np
import onnxruntime as ort
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

# pylint: disable=wrong-import-position
from dataset_schema import FrameMeta, read_model  # noqa: E402
from inspect_dumped_frames import GESTURE, YOLOX, crop_input, detect_hands  # noqa: E402


def decide(p: np.ndarray, open_enter: float, fist_enter: float) -> str:
    """Decide a single classification like the game's state machine does on entry."""
    if p[0] >= fist_enter and p[0] > p[1]:
        return "FIST"
    if p[1] >= open_enter and p[1] > p[0]:
        return "OPEN"
    return "OTHER"


def main() -> int:
    """Execute the entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("recording_dirs", nargs="+")
    parser.add_argument("--open-enter", type=float, default=0.6)
    parser.add_argument("--fist-enter", type=float, default=0.55)
    args = parser.parse_args()

    detector = ort.InferenceSession(str(YOLOX), providers=["CPUExecutionProvider"])
    classifier = ort.InferenceSession(str(GESTURE), providers=["CPUExecutionProvider"])

    samples: List[tuple] = []
    for directory in args.recording_dirs:
        for path in sorted(pathlib.Path(directory).glob("frame_*.png")):
            label = read_model(path.with_suffix(".json"), FrameMeta).label
            if label not in ("open", "fist", "other"):
                continue
            image = Image.open(path).convert("RGB")
            for box, score in detect_hands(detector, image, 320, 256, 0.4):
                samples.append((label, image, box))

    counts = {
        label: sum(1 for s in samples if s[0] == label) for label in ("open", "fist", "other")
    }
    print(f"Hand crops: {counts}")

    rotation_sets: Sequence[Sequence[int]] = [(0,), (1,), (3,), (1, 3), (0, 1, 3)]
    results = []
    for scale, rotations in itertools.product((1.0, 1.25, 1.5, 2.0), rotation_sets):
        decisions: Dict[str, Dict[str, int]] = {
            label: {"OPEN": 0, "FIST": 0, "OTHER": 0} for label in counts
        }
        for label, image, box in samples:
            sample = crop_input(image, box, scale)
            batch = np.stack([np.rot90(sample, -k) for k in rotations])[:, :, :, None]
            p = classifier.run(None, {"input": batch.astype(np.float32)})[0].mean(0)
            decisions[label][decide(p, args.open_enter, args.fist_enter)] += 1

        def rate(label: str, decision: str) -> float:
            return decisions[label][decision] / max(1, counts[label])

        results.append(
            (
                scale,
                rotations,
                rate("open", "OPEN"),
                rate("fist", "FIST"),
                rate("open", "FIST"),
                rate("fist", "OPEN"),
                rate("other", "FIST"),
                rate("other", "OPEN"),
            )
        )

    print(
        f"{'scale':>5} {'rotations':>10} {'open>OPEN':>9} {'fist>FIST':>9} "
        f"{'open>FIST':>9} {'fist>OPEN':>9} {'oth>FIST':>8} {'oth>OPEN':>8}"
    )
    for row in sorted(results, key=lambda r: -(r[2] + r[3] - 3 * r[4])):
        print(
            f"{row[0]:5.2f} {str(row[1]):>10} {row[2]:9.2f} {row[3]:9.2f} "
            f"{row[4]:9.2f} {row[5]:9.2f} {row[6]:8.2f} {row[7]:8.2f}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
