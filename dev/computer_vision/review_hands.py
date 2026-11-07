#!/usr/bin/env python3

"""
Review the automatic labels of a gameplay recording hand by hand.

The classifier, and so the automatic labels, take some hands for fists which
are not: children, especially, curl their fingers like claws while they play.
Since only real fists should throw, we look at the hands which the labeler
took for fists, and correct them.

1. Draw numbered sheets of the hands with a label (default: fist):

       venv/bin/python dev/computer_vision/review_hands.py sheets \\
           --out /tmp/review <recording> [--label fist]

2. Look at the sheets, and apply the corrections by the numbers: the hands
   which are no fists (e.g., claws) get the other label, and the hands which
   are no hands or unclear are excluded:

       venv/bin/python dev/computer_vision/review_hands.py apply <recording> \\
           --label fist --relabel 3,17,42 --exclude 5,9 --note "claws of a child"

The corrections go to labels.reviewed.json in the recording (see ReviewedHands
in dataset_schema.py), which the training applies over labels.auto.json; the
automatic labels stay as they are. A run of `apply` adds to the corrections
already there.
"""

import argparse
import pathlib
import random
import sys
from typing import List, Tuple

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

# pylint: disable=wrong-import-position
import train_fist_classifier as training  # noqa: E402
from dataset_schema import (  # noqa: E402
    AutoLabels,
    ReviewedHand,
    ReviewedHands,
    read_model,
    write_model,
)

COLUMNS = 8
ROWS = 6
CROP = 150


def hands_with(recording: pathlib.Path, label: str) -> List[Tuple[str, List[float], float]]:
    """List the hands of the label in a fixed order: (frame name, box, p(fist))."""
    labels = read_model(recording / "labels.auto.json", AutoLabels).root
    return [
        (name, hand.box, hand.p_fist)
        for name in sorted(labels)
        for hand in labels[name]
        if hand.label == label
    ]


def sheets(recording: pathlib.Path, label: str, out: pathlib.Path) -> None:
    """Draw the hands of the label, numbered, on sheets of COLUMNS x ROWS."""
    hands = hands_with(recording, label)
    font = ImageFont.load_default(size=18)
    out.mkdir(parents=True, exist_ok=True)
    per_sheet = COLUMNS * ROWS
    rng = random.Random(0)
    for first in range(0, len(hands), per_sheet):
        sheet = Image.new("RGB", (COLUMNS * (CROP + 4), ROWS * (CROP + 4)), "white")
        draw = ImageDraw.Draw(sheet)
        for k, (name, box, p) in enumerate(hands[first : first + per_sheet]):
            image = Image.open(recording / name).convert("RGB")
            crop = training.square_crop(image, box, training.CROP_SCALE, 0.0, rng)
            x, y = (k % COLUMNS) * (CROP + 4), (k // COLUMNS) * (CROP + 4)
            sheet.paste(crop.resize((CROP, CROP)), (x + 2, y + 2))
            draw.rectangle((x + 2, y + 2, x + 62, y + 24), fill="black")
            draw.text((x + 5, y + 4), f"{first + k}", fill="yellow", font=font)
        path = out / f"{recording.name}.{label}.{first // per_sheet:02d}.jpg"
        sheet.save(path, quality=90)
        print(f"Wrote {path} (hands {first}..{min(first + per_sheet, len(hands)) - 1})")
    print(f"{len(hands)} hands labeled {label} in {recording.name}")


def parse_numbers(text: str) -> List[int]:
    """Parse "3,17,40-42" into [3, 17, 40, 41, 42]."""
    numbers: List[int] = []
    for part in filter(None, (p.strip() for p in text.split(","))):
        if "-" in part:
            lo, hi = part.split("-")
            numbers.extend(range(int(lo), int(hi) + 1))
        else:
            numbers.append(int(part))
    return numbers


def apply(
    recording: pathlib.Path,
    label: str,
    relabel: List[int],
    exclude: List[int],
    note: str,
) -> None:
    """Write the corrections by the numbers of the sheets to labels.reviewed.json."""
    hands = hands_with(recording, label)
    other = "nonfist" if label == "fist" else "fist"
    path = recording / "labels.reviewed.json"
    reviewed = read_model(path, ReviewedHands).root if path.exists() else {}
    for numbers, new_label in ((relabel, other), (exclude, None)):
        for number in numbers:
            name, box, _ = hands[number]
            entries = [e for e in reviewed.get(name, []) if e.box != box]
            entries.append(ReviewedHand(box=box, label=new_label, note=note))
            reviewed[name] = entries
    write_model(path, ReviewedHands(reviewed))
    print(
        f"{recording.name}: {len(relabel)} hands relabeled as {other}, {len(exclude)} excluded; "
        f"{sum(len(v) for v in reviewed.values())} corrections in {path.name}"
    )


def main() -> int:
    """Execute the entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    sheets_parser = commands.add_parser("sheets")
    sheets_parser.add_argument("recording")
    sheets_parser.add_argument("--label", default="fist", choices=["fist", "nonfist"])
    sheets_parser.add_argument("--out", required=True)
    apply_parser = commands.add_parser("apply")
    apply_parser.add_argument("recording")
    apply_parser.add_argument("--label", default="fist", choices=["fist", "nonfist"])
    apply_parser.add_argument("--relabel", default="")
    apply_parser.add_argument("--exclude", default="")
    apply_parser.add_argument("--note", required=True)
    args = parser.parse_args()

    recording = pathlib.Path(args.recording)
    if args.command == "sheets":
        sheets(recording, args.label, pathlib.Path(args.out))
    else:
        apply(
            recording,
            args.label,
            parse_numbers(args.relabel),
            parse_numbers(args.exclude),
            args.note,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
