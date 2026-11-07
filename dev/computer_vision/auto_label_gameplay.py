#!/usr/bin/env python3

"""
Label the hands in a recorded gameplay automatically, as fist or not.

Record while playing (see CONTRIBUTING.md):

    $GODOT --path . -- --record-play

The game saves about five frames per second with the tracked hands (id, box,
velocity, the game's fist probability) and logs the game events in
events.jsonl: where each hand aims, whether over a bear, and every throw.

We combine the best classifier, run offline and smoothed over time in both
directions (offline, we can look into the future), with the evidence of the game:

* fist:
    * the smoothed classifier is very sure, or
    * the hand has just thrown (the game confirmed a fist), or it rests over
      a bear (the players close the hand there), and the classifier is
      clearly sure, too (``--event-sure``). The events alone are too weak:
      just before a throw, the hand is often still closing (a claw or a blur),
      and the players also hover over a bear with an open hand. A half-closed
      hand labeled as a fist would teach the classifier the false throws;
* not a fist:
    * the smoothed classifier is very sure, or
    * the hand was about to throw (the game had confirmed it open before),
      and the classifier does not object, or
    * the hand moves fast (aiming) and the classifier leans to open.

Everything else stays unlabeled; we would rather miss a sample than learn
a wrong one. Since the labels partly come from the classifier itself, never
evaluate on them: evaluate on the human-labeled sessions of the recorder.

The labels go to labels.auto.json in the recording, which
train_fist_classifier.py picks up; a contact sheet shows random samples of
each label for a quick check.

    venv/bin/python dev/computer_vision/auto_label_gameplay.py <recording> [<recording> ...]
"""

import argparse
import bisect
import collections
import pathlib
import random
import statistics
import sys
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageDraw

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

# pylint: disable=wrong-import-position
from dataset_schema import (  # noqa: E402
    AimsEvent,
    AutoLabel,
    AutoLabels,
    FrameMeta,
    ShotEvent,
    TrackedHand,
    read_events,
    read_model,
    write_model,
)

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
CLASSIFIER = REPO_ROOT / "scenes" / "hand_tracker" / "gesture" / "model" / "fist_classifier.onnx"
CROP_SCALE = 1.5
INPUT_SIZE = 96


class Observation:
    """One hand in one recorded frame."""

    def __init__(self, frame: pathlib.Path, time: float, hand: TrackedHand, width: int) -> None:
        self.frame = frame
        self.time = time
        self.hand_id = hand.id
        self.box = hand.box
        vx, vy = hand.velocity or [0.0, 0.0]
        # NOTE (mristin):
        # The speed in frame widths per second, independent of the resolution.
        self.speed = float(np.hypot(vx, vy)) / width
        self.p_fist = 0.0
        self.p_smoothed = 0.0
        self.over_bear = False
        self.label: Optional[str] = None
        self.reason = ""


def crop(image: Image.Image, box: List[float]) -> np.ndarray:
    """Cut the square crop around the hand like the game."""
    cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
    side = min(max(box[2] - box[0], box[3] - box[1]) * CROP_SCALE, image.width, image.height)
    x1 = min(max(cx - side / 2, 0), image.width - side)
    y1 = min(max(cy - side / 2, 0), image.height - side)
    patch = image.crop((round(x1), round(y1), round(x1 + side), round(y1 + side)))
    return np.asarray(patch.resize((INPUT_SIZE, INPUT_SIZE), Image.BILINEAR), np.float32)


def load(recording: pathlib.Path) -> Tuple[List[Observation], List[Any]]:
    """Load the confirmed hands of the recording and its events."""
    observations = []
    for meta_path in sorted(recording.glob("frame_*.json")):
        meta = read_model(meta_path, FrameMeta)
        frame = meta_path.with_suffix(".jpg")
        if not frame.exists():
            continue
        for hand in meta.hands:
            if hand.confirmed:
                observations.append(Observation(frame, meta.timestamp, hand, meta.width))

    events_path = recording / "events.jsonl"
    events = read_events(events_path) if events_path.exists() else []
    return observations, events


def classify(observations: List[Observation], model: pathlib.Path) -> None:
    """Run the best classifier on the crops."""
    session = ort.InferenceSession(str(model), providers=["CPUExecutionProvider"])
    by_frame: Dict[pathlib.Path, List[Observation]] = collections.defaultdict(list)
    for observation in observations:
        by_frame[observation.frame].append(observation)
    for frame, hands in by_frame.items():
        image = Image.open(frame).convert("RGB")
        batch = np.stack([crop(image, hand.box) for hand in hands])
        probabilities = session.run(None, {"input": batch})[0]
        for hand, p in zip(hands, probabilities):
            hand.p_fist = float(p[1])


def smooth(observations: List[Observation], half_window: float) -> None:
    """Smooth the probabilities per hand with a centered median over time."""
    by_hand: Dict[int, List[Observation]] = collections.defaultdict(list)
    for observation in observations:
        by_hand[observation.hand_id].append(observation)
    for hands in by_hand.values():
        hands.sort(key=lambda h: h.time)
        times = [h.time for h in hands]
        for hand in hands:
            lo = bisect.bisect_left(times, hand.time - half_window)
            hi = bisect.bisect_right(times, hand.time + half_window)
            hand.p_smoothed = statistics.median(h.p_fist for h in hands[lo:hi])


def attach_aims(observations: List[Observation], events: List[Any]) -> None:
    """Find out whether each hand aimed at a bear, from the nearest aim event."""
    aims = [e for e in events if isinstance(e, AimsEvent) and e.state == "PLAYING"]
    times = [e.t for e in aims]
    for observation in observations:
        i = bisect.bisect_left(times, observation.time)
        candidates = [aims[j] for j in (i - 1, i) if 0 <= j < len(aims)]
        candidates = [e for e in candidates if abs(e.t - observation.time) < 0.15]
        for event in candidates:
            for hand in event.hands:
                if hand.hand_id == observation.hand_id and hand.over_bear:
                    observation.over_bear = True


def label(observations: List[Observation], events: List[Any], args: argparse.Namespace) -> None:
    """Decide the labels from the classifier and the game, or leave them open."""
    shots: Dict[int, List[float]] = collections.defaultdict(list)
    for event in events:
        if isinstance(event, ShotEvent) and event.hand_id >= 0:
            shots[event.hand_id].append(event.t)

    for o in observations:
        p = o.p_smoothed
        hand_shots = shots.get(o.hand_id, [])
        # NOTE (mristin):
        # The game reports a throw once it has confirmed the fist, i.e., the fist
        # frames are just before the event; right after it, the players often
        # open the hand again already.
        just_threw = any(-0.3 <= o.time - t <= 0.15 for t in hand_shots)
        about_to_throw = any(0.45 <= t - o.time <= 1.2 for t in hand_shots)

        fist_reasons = []
        if p >= args.sure:
            fist_reasons.append("classifier")
        # NOTE (mristin):
        # The events of the game only confirm a fist which the classifier sees
        # clearly; on 2026-11-06, a fourth of the hands labeled by the events
        # alone were still closing (claws, blurs).
        if just_threw and p >= args.event_sure:
            fist_reasons.append("threw")
        if o.over_bear and o.speed < args.still_speed and p >= args.event_sure:
            fist_reasons.append("over a bear")

        open_reasons = []
        if p <= 1.0 - args.sure:
            open_reasons.append("classifier")
        if about_to_throw and not just_threw and p <= 0.35:
            open_reasons.append("about to throw")
        if o.speed > args.fast_speed and p <= 0.35 and not just_threw:
            open_reasons.append("moving")

        if fist_reasons and not open_reasons:
            o.label, o.reason = "fist", ", ".join(fist_reasons)
        elif open_reasons and not fist_reasons:
            o.label, o.reason = "nonfist", ", ".join(open_reasons)


def contact_sheet(observations: List[Observation], path: pathlib.Path) -> None:
    """Draw random samples of each label for a quick check by eye."""
    rng = random.Random(0)
    rows = []
    for name in ("fist", "nonfist", None):
        group = [o for o in observations if o.label == name]
        rows.append((name, rng.sample(group, min(12, len(group)))))
    sheet = Image.new("RGB", (12 * 120, 3 * 140), (30, 30, 40))
    draw = ImageDraw.Draw(sheet)
    for r, (name, group) in enumerate(rows):
        for c, o in enumerate(group):
            tile = Image.fromarray(crop(Image.open(o.frame).convert("RGB"), o.box).astype(np.uint8))
            sheet.paste(tile.resize((120, 120)), (c * 120, r * 140 + 20))
            draw.text((c * 120 + 2, r * 140 + 22), f"{o.p_smoothed:.2f}", fill=(255, 255, 0))
        draw.text((4, r * 140 + 4), str(name or "unlabeled"), fill=(255, 255, 255))
    sheet.save(path)


def main() -> int:
    """Execute the entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("recordings", nargs="+")
    parser.add_argument("--model", default=str(CLASSIFIER))
    parser.add_argument(
        "--sure", type=float, default=0.85, help="Trust the classifier alone above this"
    )
    parser.add_argument("--still-speed", type=float, default=0.15, help="Frame widths per second")
    parser.add_argument("--fast-speed", type=float, default=0.5, help="Frame widths per second")
    parser.add_argument(
        "--event-sure",
        type=float,
        default=0.9,
        help="Label a fist at a throw or over a bear only if the classifier is above this",
    )
    parser.add_argument("--half-window", type=float, default=0.4, help="Seconds of the smoothing")
    args = parser.parse_args()

    for directory in args.recordings:
        recording = pathlib.Path(directory)
        observations, events = load(recording)
        if not observations:
            print(f"{recording}: no confirmed hands, skipped")
            continue

        classify(observations, pathlib.Path(args.model))
        smooth(observations, args.half_window)
        attach_aims(observations, events)
        label(observations, events, args)

        labels: Dict[str, List[AutoLabel]] = collections.defaultdict(list)
        for o in observations:
            if o.label is not None:
                labels[o.frame.name].append(
                    AutoLabel(box=o.box, label=o.label, reason=o.reason, p_fist=o.p_smoothed)
                )
        write_model(recording / "labels.auto.json", AutoLabels(dict(labels)))
        contact_sheet(observations, recording / "labels.auto.png")

        counts = collections.Counter(o.label or "unlabeled" for o in observations)
        reasons = collections.Counter(f"{o.label}: {o.reason}" for o in observations if o.label)
        shots = sum(1 for e in events if isinstance(e, ShotEvent))
        print(f"{recording.name}: {len(observations)} hands, {shots} shots, labels {dict(counts)}")
        for reason, count in reasons.most_common():
            print(f"  {count:5d}  {reason}")
        print(f"  wrote labels.auto.json and labels.auto.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
