#!/usr/bin/env python3

"""
Find the phases of the gesture recorder where the players showed another pose
than they were asked for, to correct their labels by eye.

Children, especially, are sometimes a phase ahead or behind, or show fists
while asked for open hands. We split each session into its phases (by the
pauses of the get-ready countdown between them), classify the hands with a
model which was NOT trained on the session, and draw a contact sheet per
session: a row per phase with its label, how many hands the model agrees with,
and sample crops (green where the model agrees, red where it does not).

    venv/bin/python dev/computer_vision/review_labels.py \\
        --model <a model not trained on the sessions> \\
        --out /tmp/review ~/splash-n-splat-dataset/sessions/<session> ...

Look at the sheets, and write the corrections to labels.review.json in the
session directory (see LabelReview in dataset_schema.py): a phase gets a new
label, or None to exclude it. The training applies the corrections; the frame
files stay as recorded.
"""

import argparse
import pathlib
import sys
from typing import List, Tuple

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

# pylint: disable=wrong-import-position
import train_fist_classifier as training  # noqa: E402
from dataset_schema import FrameMeta, read_model  # noqa: E402

#: A pause between two frames longer than this starts a new phase (seconds).
PHASE_GAP = 1.2

CROPS_PER_ROW = 12
CROP = 96
ROW = CROP + 30


def phases_of(session: pathlib.Path) -> List[Tuple[str, List[pathlib.Path]]]:
    """Split the frames of a session into its phases: (label, frames)."""
    frames = sorted(list(session.glob("frame_*.jpg")) + list(session.glob("frame_*.png")))
    phases: List[Tuple[str, List[pathlib.Path]]] = []
    last_time = None
    for path in frames:
        meta = read_model(path.with_suffix(".json"), FrameMeta)
        new_phase = (
            not phases
            or meta.label != phases[-1][0]
            or (last_time is not None and meta.timestamp - last_time > PHASE_GAP)
        )
        if new_phase:
            phases.append((meta.label, []))
        phases[-1][1].append(path)
        last_time = meta.timestamp
    return phases


def review(session: pathlib.Path, model: ort.InferenceSession, out: pathlib.Path) -> None:
    """Print the agreement per phase and draw the contact sheet of the session."""
    finder = training.HandFinder(training.LABELING_DETECTOR, 0.4)
    samples = training.collect([session], finder, settle_seconds=0.0)
    x, y = training.load_crops(samples, augment=False, copies=1, seed=0)
    p = np.concatenate(
        [
            model.run(None, {"input": x[i : i + 256].astype(np.float32)})[0]
            for i in range(0, len(x), 256)
        ]
    )[:, 1]

    by_frame: dict = {}
    for i, sample in enumerate(samples):
        by_frame.setdefault(sample[1].name, []).append(i)

    phases = phases_of(session)
    font = ImageFont.load_default(size=16)
    sheet = Image.new("RGB", (CROPS_PER_ROW * (CROP + 4) + 8, len(phases) * ROW + 8), "white")
    draw = ImageDraw.Draw(sheet)
    print(f"== {session.name}")
    for row, (label, frames) in enumerate(phases):
        hands = [i for frame in frames for i in by_frame.get(frame.name, [])]
        agree = [(p[i] >= 0.5) == (y[i] == 1) for i in hands]
        share = float(np.mean(agree)) if agree else float("nan")
        mark = "  <-- check" if agree and share < 0.6 else ""
        print(
            f"phase {row:2d}  {frames[0].stem}..{frames[-1].stem}  {label:26s} "
            f"{len(hands):3d} hands, model agrees {share:4.0%}{mark}"
        )

        top = 4 + row * ROW
        draw.text(
            (6, top),
            f"#{row} {frames[0].stem}..{frames[-1].stem}  {label}  agrees {share:.0%}",
            fill="black",
            font=font,
        )
        if not hands:
            continue
        picks = [hands[int(k)] for k in np.linspace(0, len(hands) - 1, CROPS_PER_ROW)]
        for k, i in enumerate(picks):
            crop = Image.fromarray(x[i]).resize((CROP, CROP))
            left = 4 + k * (CROP + 4)
            ok = (p[i] >= 0.5) == (y[i] == 1)
            draw.rectangle(
                (left - 2, top + 22, left + CROP + 1, top + 24 + CROP + 1),
                fill=(40, 170, 60) if ok else (220, 40, 40),
            )
            sheet.paste(crop, (left, top + 24))
            draw.text((left + 3, top + 26), f"{p[i]:.2f}", fill="yellow", font=font)

    out.mkdir(parents=True, exist_ok=True)
    path = out / f"{session.name}.review.jpg"
    sheet.save(path, quality=90)
    print(f"Wrote {path}")


def main() -> int:
    """Execute the entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sessions", nargs="+")
    parser.add_argument("--model", default=str(training.MODEL_DIR / "fist_classifier.onnx"))
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    model = ort.InferenceSession(args.model, providers=["CPUExecutionProvider"])
    for session in args.sessions:
        review(pathlib.Path(session), model, pathlib.Path(args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
