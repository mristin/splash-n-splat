#!/usr/bin/env python3

"""
Validate every JSON file of a dataset directory against the schema, and write
its manifest (the recordings, their labels, and the SHA-256 of every file).

    venv/bin/python dev/computer_vision/check_dataset.py ~/splash-n-splat-dataset

The dataset holds sessions/ (gesture recorder), gameplay/ (gameplay with
automatic labels) and split.json; see dataset_schema.py.
"""

import argparse
import collections
import hashlib
import pathlib
import sys
from typing import Dict, List

from pydantic import ValidationError

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

# pylint: disable=wrong-import-position
from dataset_schema import (  # noqa: E402
    AutoLabels,
    DatasetManifest,
    FrameMeta,
    HandCache,
    ScoredHandCache,
    LabelReview,
    ReviewedHands,
    SessionSummary,
    Split,
    read_events,
    read_model,
    write_model,
)


def check_recording(recording: pathlib.Path, kind: str, errors: List[str]) -> SessionSummary:
    """Validate the files of a recording and summarize its labels."""
    labels: Dict[str, int] = collections.Counter()
    frames = 0
    for meta_path in sorted(recording.glob("frame_*.json")):
        frames += 1
        try:
            meta = read_model(meta_path, FrameMeta)
        except ValidationError as error:
            errors.append(f"{meta_path}: {error}")
            continue
        if kind == "sessions":
            labels[meta.label] += 1
        image = meta_path.with_suffix(".jpg")
        if not image.exists() and not meta_path.with_suffix(".png").exists():
            errors.append(f"{meta_path}: the image is missing")

    for cache_path in recording.glob("hands.*.json"):
        try:
            read_model(cache_path, HandCache)
        except ValidationError as error:
            errors.append(f"{cache_path}: {error}")
    for cache_path in recording.glob("scored_hands.*.json"):
        try:
            read_model(cache_path, ScoredHandCache)
        except ValidationError as error:
            errors.append(f"{cache_path}: {error}")

    review_path = recording / "labels.review.json"
    if review_path.exists():
        try:
            review = read_model(review_path, LabelReview)
            stems = {path.stem for path in recording.glob("frame_*.json")}
            for phase in review.phases:
                for stem in (phase.first, phase.last):
                    if stem not in stems:
                        errors.append(f"{review_path}: the frame {stem} does not exist")
        except ValidationError as error:
            errors.append(f"{review_path}: {error}")

    reviewed_path = recording / "labels.reviewed.json"
    if reviewed_path.exists():
        try:
            auto_path = recording / "labels.auto.json"
            auto = read_model(auto_path, AutoLabels).root if auto_path.exists() else {}
            for name, hands in read_model(reviewed_path, ReviewedHands).root.items():
                boxes = [hand.box for hand in auto.get(name, [])]
                for hand in hands:
                    if hand.box not in boxes:
                        errors.append(
                            f"{reviewed_path}: {name} has no automatic label at {hand.box}"
                        )
        except ValidationError as error:
            errors.append(f"{reviewed_path}: {error}")

    auto_path = recording / "labels.auto.json"
    if auto_path.exists():
        try:
            for hands in read_model(auto_path, AutoLabels).root.values():
                for hand in hands:
                    labels[hand.label] += 1
        except ValidationError as error:
            errors.append(f"{auto_path}: {error}")

    events_path = recording / "events.jsonl"
    if events_path.exists():
        try:
            read_events(events_path)
        except ValueError as error:
            errors.append(str(error))

    return SessionSummary(kind=kind, frames=frames, labels=dict(labels))


def main() -> int:
    """Execute the entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset")
    args = parser.parse_args()

    root = pathlib.Path(args.dataset)
    errors: List[str] = []

    recordings: Dict[str, SessionSummary] = {}
    for kind in ("sessions", "gameplay"):
        if (root / kind).is_dir():
            for recording in sorted(p for p in (root / kind).iterdir() if p.is_dir()):
                recordings[f"{kind}/{recording.name}"] = check_recording(recording, kind, errors)

    split_path = root / "split.json"
    if not split_path.exists():
        errors.append(f"{split_path} is missing")
    else:
        try:
            split = read_model(split_path, Split)
            for name in split.test:
                if name not in recordings:
                    errors.append(f"{split_path}: the test recording {name} does not exist")
                elif recordings[name].kind == "gameplay":
                    errors.append(f"{split_path}: {name} has automatic labels; never test on it")
        except ValidationError as error:
            errors.append(f"{split_path}: {error}")

    if errors:
        for error in errors[:30]:
            print(f"ERROR: {error}", file=sys.stderr)
        print(f"{len(errors)} error(s); the manifest was not written.", file=sys.stderr)
        return 1

    files = {
        str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(root.rglob("*"))
        if path.is_file() and path.name != "manifest.json"
    }
    write_model(root / "manifest.json", DatasetManifest(recordings=recordings, files=files))

    for name, summary in recordings.items():
        print(f"{name}: {summary.frames} frames, {summary.labels}")
    print(f"All {len(files)} files valid; wrote {root / 'manifest.json'}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
