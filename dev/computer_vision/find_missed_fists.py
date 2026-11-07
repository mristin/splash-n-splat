#!/usr/bin/env python3

"""
Find the fists which the game missed in a gameplay recording: a player whose
fist does not throw tries again and again, closing the hand repeatedly in about
the same place.

    venv/bin/python dev/computer_vision/find_missed_fists.py \\
        --out /tmp/missed <recording> [<recording> ...]

For every tracked hand, we look for closings: the box of the hand shrinks
clearly (a fist is smaller than an open hand) and grows again. A closing
threw if the hand threw up to a second before the smallest box (the fist is
confirmed while the hand still closes) or shortly after it. A stretch with at least two
closings which did not throw within a few seconds, while the hand stays in
about the same place, is a repeated attempt (often ended by a throw at last). The box does not depend on the
classifier, so we also find the fists which the classifier did not see at all.

We print the attempts and draw a sheet per recording: a row per attempt with
the crops of the hand over time (the closings framed in red) and the curves of
the box size (blue) and of the fist probability of the game (red). The
closings are the hard fists to review and to train on.
"""

import argparse
import collections
import pathlib
import random
import sys
from typing import Dict, List, Tuple

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

# pylint: disable=wrong-import-position
import train_fist_classifier as training  # noqa: E402
from dataset_schema import FrameMeta, ShotEvent, read_events, read_model  # noqa: E402

#: A closing: the box shrinks to this fraction of its size of the last second.
SHRINK = 0.8
#: ... and grows back by this factor within the next second.
REGROW = 1.12
#: An attempt: at least this many closings within this many seconds,
MIN_CLOSINGS = 2
WINDOW = 4.0
#: ... while the hand moves less than this fraction of the frame width,
STATIONARY = 0.12
#: A closing is missed if the hand does not throw from shortly before it to
#: shortly after it; the final, successful closing of an attempt does not count.
SHOT_BEFORE = 1.0
SHOT_AFTER = 0.8

CROP = 110
CROPS_PER_ROW = 14
PLOT = 70

Sample = Tuple[float, pathlib.Path, List[float], float]


def tracks_of(recording: pathlib.Path) -> Dict[int, List[Sample]]:
    """Read the samples of every tracked hand: (time, frame, box, p(fist) of the game)."""
    tracks: Dict[int, List[Sample]] = collections.defaultdict(list)
    for path in sorted(recording.glob("frame_*.jpg")):
        meta = read_model(path.with_suffix(".json"), FrameMeta)
        for hand in meta.hands:
            if hand.confirmed:
                tracks[hand.id].append((meta.timestamp, path, hand.box, hand.fist or 0.0))
    return tracks


def area(box: List[float]) -> float:
    return max(1.0, (box[2] - box[0]) * (box[3] - box[1]))


def closings_of(samples: List[Sample]) -> List[int]:
    """Find the indices of the samples where the hand closes."""
    result = []
    for i, (t, _, box, _) in enumerate(samples):
        before = [area(s[2]) for s in samples if t - 1.0 <= s[0] < t]
        after = [area(s[2]) for s in samples if t < s[0] <= t + 1.0]
        a = area(box)
        neighbors = [area(s[2]) for s in samples[max(0, i - 1) : i + 2]]
        is_minimum = a <= min(neighbors)
        shrinks = bool(before) and a <= SHRINK * max(before)
        regrows = bool(after) and max(after) >= REGROW * a
        # NOTE (mristin):
        # We go by the box only: the fist probability of the game also jumps on
        # open hands, and it does not rise at all on the fists which the
        # classifier misses, which are the ones we look for.
        if is_minimum and shrinks and regrows:
            if not result or t - samples[result[-1]][0] > 0.4:
                result.append(i)
    return result


def attempts_of(
    samples: List[Sample], shots: List[float], width: int
) -> List[Tuple[int, int, List[int]]]:
    """Find the repeated attempts of a hand: (first index, last index, closings)."""
    closings = [
        c
        for c in closings_of(samples)
        if not any(-SHOT_BEFORE <= shot - samples[c][0] <= SHOT_AFTER for shot in shots)
    ]
    attempts: List[Tuple[int, int, List[int]]] = []
    for k, start in enumerate(closings):
        t0 = samples[start][0]
        group = [c for c in closings[k:] if samples[c][0] - t0 <= WINDOW]
        if len(group) < MIN_CLOSINGS:
            continue
        t1 = samples[group[-1]][0]
        span = [s for s in samples if t0 - 0.5 <= s[0] <= t1 + 0.5]
        xs = [(s[2][0] + s[2][2]) / 2 for s in span]
        ys = [(s[2][1] + s[2][3]) / 2 for s in span]
        if max(max(xs) - min(xs), max(ys) - min(ys)) > STATIONARY * width:
            continue
        first = next(i for i, s in enumerate(samples) if s[0] >= t0 - 0.5)
        last = max(i for i, s in enumerate(samples) if s[0] <= t1 + 0.5)
        if attempts and first <= attempts[-1][1]:
            previous = attempts.pop()
            merged = sorted(set(previous[2]) | set(group))
            attempts.append((previous[0], max(previous[1], last), merged))
        else:
            attempts.append((first, last, group))
    return attempts


def draw(
    recording: pathlib.Path,
    rows: List[Tuple[int, List[Sample], int, int, List[int]]],
    out: pathlib.Path,
) -> None:
    """Draw a row per attempt: the crops over time and the curves below."""
    font = ImageFont.load_default(size=14)
    row_height = 22 + CROP + PLOT + 12
    sheet = Image.new(
        "RGB", (CROPS_PER_ROW * (CROP + 4) + 8, max(1, len(rows)) * row_height), "white"
    )
    d = ImageDraw.Draw(sheet)
    rng = random.Random(0)
    for r, (hand_id, samples, first, last, closings) in enumerate(rows):
        top = r * row_height
        # NOTE (mristin):
        # Every closing gets a crop; the other crops fill the row evenly.
        span = list(range(first, last + 1))
        if len(span) > CROPS_PER_ROW:
            keep = set(closings)
            rest = [i for i in span if i not in keep]
            free = max(0, CROPS_PER_ROW - len(keep))
            step = len(rest) / max(1, free)
            keep |= {rest[int(k * step)] for k in range(free)}
            span = sorted(keep)[:CROPS_PER_ROW]
        t0, t1 = samples[first][0], samples[last][0]
        d.text(
            (6, top + 2),
            f"hand {hand_id}  {samples[first][1].stem}..{samples[last][1].stem}  "
            f"{t1 - t0:.1f} s, {len(closings)} closings without a throw",
            fill="black",
            font=font,
        )
        for k, i in enumerate(span):
            t, path, box, p = samples[i]
            crop = training.square_crop(
                Image.open(path).convert("RGB"), box, training.CROP_SCALE, 0.0, rng
            )
            left = 4 + k * (CROP + 4)
            if i in closings:
                d.rectangle(
                    (left - 2, top + 20, left + CROP + 1, top + 22 + CROP + 1), fill=(220, 40, 40)
                )
            sheet.paste(crop.resize((CROP, CROP)), (left, top + 22))
            d.text((left + 3, top + 24), f"{p:.2f}", fill="yellow", font=font)

        # The curves of the box size (blue) and the fist probability (red) over the attempt
        width = CROPS_PER_ROW * (CROP + 4)
        base = top + 22 + CROP + 6
        d.rectangle((4, base, 4 + width, base + PLOT), outline=(200, 200, 200))
        areas = [area(samples[i][2]) for i in range(first, last + 1)]
        lo, hi = min(areas), max(areas)
        duration = max(1e-3, t1 - t0)
        for values, color, scale in (
            (areas, (40, 90, 220), lambda v: (v - lo) / max(1.0, hi - lo)),
            ([samples[i][3] for i in range(first, last + 1)], (220, 40, 40), lambda v: v),
        ):
            points = [
                (4 + width * (samples[i][0] - t0) / duration, base + PLOT - PLOT * scale(v))
                for i, v in zip(range(first, last + 1), values)
            ]
            if len(points) > 1:
                d.line(points, fill=color, width=2)
        for i in closings:
            x = 4 + width * (samples[i][0] - t0) / duration
            d.line((x, base, x, base + PLOT), fill=(220, 40, 40), width=1)

    out.mkdir(parents=True, exist_ok=True)
    path = out / f"{recording.name}.missed.jpg"
    sheet.save(path, quality=90)
    print(f"Wrote {path}")


def main() -> int:
    """Execute the entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("recordings", nargs="+")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    for directory in args.recordings:
        recording = pathlib.Path(directory)
        shots: Dict[int, List[float]] = collections.defaultdict(list)
        for event in read_events(recording / "events.jsonl"):
            if isinstance(event, ShotEvent):
                shots[event.hand_id].append(event.t)

        first_meta = read_model(next(iter(sorted(recording.glob("frame_*.json")))), FrameMeta)
        rows = []
        for hand_id, samples in sorted(tracks_of(recording).items()):
            for first, last, closings in attempts_of(samples, shots[hand_id], first_meta.width):
                rows.append((hand_id, samples, first, last, closings))
                print(
                    f"{recording.name}: hand {hand_id}, {samples[first][1].stem}..{samples[last][1].stem}, "
                    f"{len(closings)} closings without a throw"
                )
        print(f"{recording.name}: {len(rows)} repeated attempts")
        draw(recording, rows, pathlib.Path(args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
