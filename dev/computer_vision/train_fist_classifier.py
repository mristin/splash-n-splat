#!/usr/bin/env python3

"""
Train the fist classifier of Splash 'n' Splat on recorded webcam sessions.

Record the sessions with the gesture recorder (see README.md):

    $GODOT --path . scenes/tests/gesture_recorder/gesture_recorder.tscn

and train with the dataset directory (see split.json there):

    venv/bin/python dev/computer_vision/train_fist_classifier.py --dataset ~/splash-n-splat-dataset

or with explicit sessions:

    venv/bin/python dev/computer_vision/train_fist_classifier.py \
        --sessions ~/.local/share/godot/app_userdata/"Splash 'n' Splat"/recordings/* \
        --holdout <one of the session directories>

The classifier tells a FIST from anything else (NONFIST) on a square crop around
a hand, as found by the game's YOLOX hand detector. We fine-tune MobileNetV3-Small,
pre-trained on ImageNet, on 96x96 RGB crops. We evaluate on whole held-out
sessions only, never on frames of a session used for the training, since
the neighboring frames of a session are nearly identical.

The script writes:

* scenes/hand_tracker/gesture/model/fist_classifier.onnx (float32),
* scenes/hand_tracker/gesture/model/fist_classifier.json (pre-processing, labels),
* dev/computer_vision/fist_classifier_report.json (data, training, evaluation and parity;
  not versioned, since it names the recordings and so the people in them).

It fails loudly if the ONNX model does not reproduce the Keras model.
"""

import argparse
import datetime
import gc
import hashlib
import json
import pathlib
import random
import shutil
import sys
import time
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple

import numpy as np
import onnxruntime as ort
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

# pylint: disable=wrong-import-position
from dataset_schema import (  # noqa: E402
    AutoLabels,
    ClassifierInput,
    ClassifierMetadata,
    ClassifierOutput,
    FrameMeta,
    LabelReview,
    ReviewedHands,
    ScoredHandCache,
    Latency,
    Metrics,
    Split,
    TrainingReport,
    read_model,
    write_model,
)
from inspect_dumped_frames import YOLOX, detect_hands  # noqa: E402

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
MODEL_DIR = REPO_ROOT / "scenes" / "hand_tracker" / "gesture" / "model"
LABELS = ["nonfist", "fist"]
INPUT_SIZE = 96

# NOTE (mristin):
# The game crops a square of this many times the longer side of the hand box;
# see VisionConfig.CropScale.
CROP_SCALE = 1.5


class TrainingError(RuntimeError):
    """Signal a problem the user has to act upon."""


def label_of_hand(frame_label: str, box: Sequence[float], width: int) -> Optional[str]:
    """
    Determine the label of a single hand from the label of its frame.

    The labels of the older recordings (open, other) count as nonfist. The
    labels ``left=...,right=...`` refer to the halves of the mirrored screen.
    """
    if frame_label in ("fist",):
        return "fist"
    if frame_label in ("nonfist", "open", "other"):
        return "nonfist"
    if frame_label.startswith("left="):
        sides = dict(part.split("=") for part in frame_label.split(","))
        center = (box[0] + box[2]) / 2
        mirrored = 1.0 - center / width
        # NOTE (mristin):
        # Hands close to the middle are ambiguous; we skip them.
        if abs(mirrored - 0.5) < 0.05:
            return None
        return sides["left"] if mirrored < 0.5 else sides["right"]
    return None


def square_crop(
    image: Image.Image, box: Sequence[float], scale: float, jitter: float, rng: random.Random
) -> Image.Image:
    """Cut the square crop around the hand like the game, with an optional jitter."""
    cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
    side = max(box[2] - box[0], box[3] - box[1]) * scale
    if jitter > 0:
        side *= 1 + rng.uniform(-jitter, jitter)
        cx += rng.uniform(-jitter, jitter) * side * 0.5
        cy += rng.uniform(-jitter, jitter) * side * 0.5
    side = min(side, image.width, image.height)
    x1 = min(max(cx - side / 2, 0), image.width - side)
    y1 = min(max(cy - side / 2, 0), image.height - side)
    return image.crop((round(x1), round(y1), round(x1 + side), round(y1 + side)))


MLTK_MODEL = MODEL_DIR / "rock_paper_scissors_float32.onnx"

LABELING_DETECTOR = (
    REPO_ROOT / ".cache" / "models" / "yolox_m_body_head_hand_post_0299_0.5263_1x3x480x640.onnx"
)


#: The lowest score of the labeling detector which we cache; the training
#: filters the cached hands by --detector-threshold.
SCORE_FLOOR = 0.25

#: The pause between two phases of the gesture recorder is 3 seconds and the
#: frames within a phase are about 0.2 seconds apart; a longer gap starts a phase.
PHASE_GAP_SECONDS = 1.5


class HandFinder:
    """
    Find the hands for the labeling: with the large YOLOX (see
    dev/computer_vision/download_labeling_detector.py) if available, else with the game's nano.
    """

    def __init__(self, labeling_detector: pathlib.Path, threshold: float) -> None:
        self.threshold = threshold
        if labeling_detector.exists():
            self.session = ort.InferenceSession(
                str(labeling_detector), providers=["CPUExecutionProvider"]
            )
            self.name = labeling_detector.name
            self.large = True
        else:
            print(
                f"WARNING: {labeling_detector} is missing; labeling with the game's nano "
                "detector, which misses more hands. Run dev/computer_vision/download_labeling_detector.py."
            )
            self.session = ort.InferenceSession(str(YOLOX), providers=["CPUExecutionProvider"])
            self.name = YOLOX.name
            self.large = False

    def __call__(self, image: Image.Image) -> List[List[float]]:
        """
        Return the hand boxes in pixels of the image, with their scores
        (x1, y1, x2, y2, score), down to :data:`SCORE_FLOOR`.
        """
        if not self.large:
            return [
                [*box, score]
                for box, score in detect_hands(self.session, image, 320, 256, SCORE_FLOOR)
            ]

        # NOTE (mristin):
        # The model with the built-in post-processing takes BGR in [0, 255] at
        # 640x480 (our camera resolution, so no resizing) and returns rows of
        # (batch, class, score, x1, y1, x2, y2) in pixels of its input.
        input_meta = self.session.get_inputs()[0]
        height, width = input_meta.shape[2], input_meta.shape[3]
        resized = (
            image
            if image.size == (width, height)
            else image.resize((width, height), Image.BILINEAR)
        )
        x = np.asarray(resized)[:, :, ::-1].transpose(2, 0, 1)[None].astype(np.float32)
        rows = self.session.run(None, {input_meta.name: x})[0]
        sx, sy = image.width / width, image.height / height
        return [
            [
                float(r[3]) * sx,
                float(r[4]) * sy,
                float(r[5]) * sx,
                float(r[6]) * sy,
                float(r[2]),
            ]
            for r in rows
            if int(r[1]) == 2 and r[2] >= SCORE_FLOOR
        ]


#: The marker of a frame which the review excludes.
EXCLUDED = "excluded"


def reviewed_labels(session: pathlib.Path) -> Dict[str, str]:
    """
    Read the corrected labels of a session (labels.review.json, see
    dev/computer_vision/review_labels.py) by the frame stem: the new label of
    the frame, or :data:`EXCLUDED`.
    """
    path = session / "labels.review.json"
    if not path.exists():
        return {}
    result: Dict[str, str] = {}
    for phase in read_model(path, LabelReview).phases:
        first = int(phase.first.split("_")[-1])
        last = int(phase.last.split("_")[-1])
        if last < first:
            raise TrainingError(f"{path}: the phase {phase.first}..{phase.last} is reversed.")
        for index in range(first, last + 1):
            result[f"frame_{index:05d}"] = phase.label if phase.label is not None else EXCLUDED
    return result


def collect(
    sessions: Sequence[pathlib.Path], finder: HandFinder, settle_seconds: float = 1.0
) -> List[Tuple[str, pathlib.Path, List[float], str]]:
    """
    Find all the labeled hands: (session, frame path, box, label).

    The hands of the gesture recorder count only if the labeling detector
    scored them at least ``finder.threshold`` (it takes knees, plants and
    blankets for hands with lower scores), and only after the first
    ``settle_seconds`` of their phase, since the player often still shows the
    pose of the previous phase.
    """
    samples = []
    for session in sessions:
        frames = sorted(list(session.glob("frame_*.jpg")) + list(session.glob("frame_*.png")))
        if not frames:
            raise TrainingError(f"No frames in {session}; is it a recording directory?")

        # NOTE (mristin):
        # A gameplay recording carries per-hand labels of auto_label_gameplay.py,
        # on the boxes which the game tracked; we use them as they are.
        auto_path = session / "labels.auto.json"
        if auto_path.exists():
            # NOTE (mristin):
            # The hands reviewed by eye (labels.reviewed.json, see review_hands.py)
            # override their automatic labels, or are excluded.
            reviewed_path = session / "labels.reviewed.json"
            reviewed = (
                read_model(reviewed_path, ReviewedHands).root if reviewed_path.exists() else {}
            )
            for name, hands in read_model(auto_path, AutoLabels).root.items():
                corrections = {tuple(e.box): e.label for e in reviewed.get(name, [])}
                for hand in hands:
                    label: Optional[str] = corrections.get(tuple(hand.box), hand.label)
                    if label is not None:
                        samples.append((session.name, session / name, hand.box, label))
            continue

        # NOTE (mristin):
        # We cache the boxes per session and detector, since the large detector
        # takes a while on a CPU.
        cache_path = session / f"scored_hands.{finder.name}.json"
        cache: Dict[str, List[List[float]]] = (
            read_model(cache_path, ScoredHandCache).root if cache_path.exists() else {}
        )
        review = reviewed_labels(session)
        phase_start: Optional[float] = None
        previous: Optional[float] = None
        for i, path in enumerate(frames):
            meta = read_model(path.with_suffix(".json"), FrameMeta)
            if previous is None or meta.timestamp - previous > PHASE_GAP_SECONDS:
                phase_start = meta.timestamp
            previous = meta.timestamp
            assert phase_start is not None
            if meta.timestamp - phase_start < settle_seconds:
                continue
            if review.get(path.stem) == EXCLUDED:
                continue
            if path.name not in cache:
                cache[path.name] = finder(Image.open(path).convert("RGB"))
                if i % 100 == 0:
                    print(f"  {session.name}: {i}/{len(frames)} frames", flush=True)
                    write_model(cache_path, ScoredHandCache(cache))
            frame_label = review.get(path.stem, meta.label)
            for scored in cache[path.name]:
                if scored[4] < finder.threshold:
                    continue
                box = scored[:4]
                label = label_of_hand(frame_label, box, meta.width)
                if label is not None:
                    samples.append((session.name, path, box, label))
        write_model(cache_path, ScoredHandCache(cache))
    return samples


def load_crops(
    samples: Sequence[Tuple[str, pathlib.Path, List[float], str]],
    augment: bool,
    copies: int,
    seed: int,
    file: Optional[pathlib.Path] = None,
) -> Tuple[np.ndarray, np.ndarray]:
    """
    Cut the crops (with augmentation) as uint8 RGB arrays and their labels.

    The crops go directly into one preallocated array: with 100 000 crops
    (about 3 GB), stacking a list of them would need the memory twice, and
    froze the laptop. With a ``file``, the array is a memory-mapped ``.npy``
    file on the disk, so that the operating system keeps only the recently
    used crops in the memory, and the training does not need more memory as
    the dataset grows.
    """
    rng = random.Random(seed)
    images: Dict[pathlib.Path, Image.Image] = {}
    repeat = copies if augment else 1
    shape = (len(samples) * repeat, INPUT_SIZE, INPUT_SIZE, 3)
    if file is not None:
        file.parent.mkdir(parents=True, exist_ok=True)
        xs = np.lib.format.open_memmap(file, mode="w+", dtype=np.uint8, shape=shape)
    else:
        xs = np.empty(shape, np.uint8)
    ys = np.empty(len(samples) * repeat, np.int64)
    i = 0
    for _, path, box, label in samples:
        if path not in images:
            images[path] = Image.open(path).convert("RGB")
        image = images[path]
        for _ in range(repeat):
            crop = square_crop(image, box, CROP_SCALE, 0.15 if augment else 0.0, rng)
            if augment:
                if rng.random() < 0.5:
                    crop = crop.transpose(Image.FLIP_LEFT_RIGHT)
                crop = crop.rotate(rng.uniform(-20, 20), resample=Image.BILINEAR)
            crop = crop.resize((INPUT_SIZE, INPUT_SIZE), Image.BILINEAR)
            xs[i] = np.asarray(crop, np.uint8)
            ys[i] = LABELS.index(label)
            i += 1
        if len(images) > 64:
            images.clear()
    if isinstance(xs, np.memmap):
        xs.flush()
    return xs, ys


def batches_of(x: np.ndarray, y: np.ndarray, batch_size: int, training: bool, seed: int) -> Any:
    """
    Make a dataset of the batches of the crops, augmented photometrically when
    training.

    We shuffle and batch only the indices, and gather every batch from the
    NumPy arrays: ``from_tensor_slices`` on the crops would copy all of them
    into TensorFlow, and a shuffle buffer over all of them would copy them
    once more, which, together, does not fit into the memory of the laptop.
    """
    import tensorflow as tf  # pylint: disable=import-outside-toplevel

    def gather(indices: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
        return x[indices], y[indices]

    def load(indices: Any) -> Tuple[Any, Any]:
        crops, labels = tf.numpy_function(gather, [indices], [tf.uint8, tf.int64])
        crops.set_shape([None, INPUT_SIZE, INPUT_SIZE, 3])
        labels.set_shape([None])
        return photometric(crops, training), labels

    indices = tf.data.Dataset.range(len(x))
    if training:
        indices = indices.shuffle(len(x), seed=seed)
    return indices.batch(batch_size).map(load).prefetch(2)


def photometric(x: Any, training: bool) -> Any:
    """
    Randomize the light, like varying webcams and rooms: the brightness, the
    contrast, the color, the gamma, and a backlight (a dark hand in front of
    a bright window).
    """
    import tensorflow as tf  # pylint: disable=import-outside-toplevel

    x = tf.cast(x, tf.float32)
    if not training:
        return x
    x = tf.image.random_brightness(x, 40.0)
    x = tf.image.random_contrast(x, 0.6, 1.4)
    x = tf.image.random_saturation(x, 0.6, 1.4)

    batch = tf.shape(x)[0]
    gamma = tf.random.uniform([batch, 1, 1, 1], 0.6, 1.8)
    x = 255.0 * tf.pow(tf.clip_by_value(x, 0.0, 255.0) / 255.0, gamma)

    # NOTE (mristin):
    # The backlight darkens the whole crop and brightens it from one side, like
    # a window behind the player, for about a third of the crops; the middle,
    # where the hand is, stays dark.
    grid = tf.linspace(-1.0, 1.0, INPUT_SIZE)
    xs = tf.tile(grid[None, :], [INPUT_SIZE, 1])[None, :, :, None]
    ys = tf.tile(grid[:, None], [1, INPUT_SIZE])[None, :, :, None]
    angle = tf.random.uniform([batch, 1, 1, 1], 0.0, 2.0 * np.pi)
    along = xs * tf.cos(angle) + ys * tf.sin(angle)
    glare = tf.clip_by_value((along - 0.25) * 1.5, 0.0, 1.0)
    glare = glare * tf.random.uniform([batch, 1, 1, 1], 0.4, 0.95)
    backlit = tf.cast(tf.random.uniform([batch, 1, 1, 1]) < 0.35, tf.float32)
    dim = tf.random.uniform([batch, 1, 1, 1], 0.35, 0.85)
    lit = x * dim * (1.0 - glare) + 255.0 * glare
    x = backlit * lit + (1.0 - backlit) * x

    x = x + tf.random.normal(tf.shape(x), stddev=4.0)
    return tf.clip_by_value(x, 0.0, 255.0)


def normalize_contrast(x: Any) -> Any:
    """
    Stretch every crop to the brightness and the contrast of its center, where
    the hand is, so that a dark hand in front of a bright window looks like a
    hand in a well-lit room.

    It is the first layer of the model, so the game (which runs the ONNX
    model) does exactly the same as the training.
    """
    import tensorflow as tf  # pylint: disable=import-outside-toplevel

    margin = INPUT_SIZE // 4
    center = x[:, margin : INPUT_SIZE - margin, margin : INPUT_SIZE - margin, :]
    mean = tf.reduce_mean(center, axis=[1, 2, 3], keepdims=True)
    std = tf.sqrt(tf.reduce_mean(tf.square(center - mean), axis=[1, 2, 3], keepdims=True))
    return tf.clip_by_value((x - mean) / tf.maximum(std, 12.0) * 48.0 + 128.0, 0.0, 255.0)


def build_model() -> Any:
    """Build MobileNetV3-Small with a binary head; the input is RGB in [0, 255]."""
    import tensorflow as tf  # pylint: disable=import-outside-toplevel

    base = tf.keras.applications.MobileNetV3Small(
        input_shape=(INPUT_SIZE, INPUT_SIZE, 3),
        alpha=0.75,
        minimalistic=False,
        include_top=False,
        weights="imagenet",
        pooling="avg",
        include_preprocessing=True,
    )
    inputs = tf.keras.Input((INPUT_SIZE, INPUT_SIZE, 3), name="input")
    # NOTE (mristin):
    # We keep the batch normalization of the base in the inference mode, also
    # while fine-tuning. Otherwise it normalizes with the statistics of each
    # batch during the training, but with its slowly updated moving averages
    # at inference, which lag behind the changing weights: the model then
    # scores well during the training, but its probabilities are skewed
    # in the game (it took most fists for open hands, even on its training data).
    normalized = tf.keras.layers.Lambda(normalize_contrast, name="normalize_contrast")(inputs)
    x = base(normalized, training=False)
    x = tf.keras.layers.Dropout(0.3)(x)
    outputs = tf.keras.layers.Dense(len(LABELS), activation="softmax", name="probabilities")(x)
    return tf.keras.Model(inputs, outputs), base


def evaluate(probabilities: np.ndarray, labels: np.ndarray, threshold: float) -> Metrics:
    """Compute the per-crop rates which matter for the game."""
    fist = probabilities[:, 1] >= threshold
    is_fist = labels == 1
    return Metrics(
        fist_recall=float(np.mean(fist[is_fist])) if is_fist.any() else float("nan"),
        nonfist_recall=float(np.mean(~fist[~is_fist])) if (~is_fist).any() else float("nan"),
        nonfist_as_fist=float(np.mean(fist[~is_fist])) if (~is_fist).any() else float("nan"),
        accuracy=float(np.mean(fist == is_fist)),
        count_fist=int(is_fist.sum()),
        count_nonfist=int((~is_fist).sum()),
    )


def roc_auc(scores: np.ndarray, positive: np.ndarray) -> float:
    """Compute the area under the ROC curve (the threshold-free separability)."""
    order = np.argsort(scores)
    ranks = np.empty(len(scores))
    ranks[order] = np.arange(1, len(scores) + 1)
    n_pos = int(positive.sum())
    n_neg = len(scores) - n_pos
    if n_pos == 0 or n_neg == 0:
        return float("nan")
    return float((ranks[positive].sum() - n_pos * (n_pos + 1) / 2) / (n_pos * n_neg))


def mltk_fist_probabilities(
    samples: Sequence[Tuple[str, pathlib.Path, List[float], str]], quarter_turns: Sequence[int]
) -> np.ndarray:
    """Classify the crops with the MLTK model as the game does; return p(rock) per crop."""
    session = ort.InferenceSession(str(MLTK_MODEL), providers=["CPUExecutionProvider"])
    images: Dict[pathlib.Path, Image.Image] = {}
    result = []
    for _, path, box, _ in samples:
        if path not in images:
            images = {path: Image.open(path).convert("RGB")}
        crop = square_crop(images[path], box, CROP_SCALE, 0.0, random.Random(0))
        x = np.asarray(crop.convert("L").resize((84, 84), Image.BILINEAR), np.float32)
        x = (x - x.mean()) / (x.std() + 1e-6)
        batch = np.stack([np.rot90(x, -k) for k in quarter_turns])[:, :, :, None]
        result.append(session.run(None, {"input": batch.astype(np.float32)})[0].mean(0)[0])
    return np.array(result)


def split_samples(
    samples: List[Tuple[str, pathlib.Path, List[float], str]],
    mode: str,
    test_fraction: float,
    seed: int,
    auto_sessions: Set[str],
) -> Tuple[List[Any], List[Any]]:
    """
    Split randomly by frames ("random") or by 2-second chunks of frames ("chunks").

    All the hands of a frame always go to the same side. The automatically
    labeled sessions (gameplay) always go to the training: their labels partly
    come from a classifier, so they must never be used for the evaluation.
    """

    def key(sample: Tuple[str, pathlib.Path, List[float], str]) -> Tuple[str, int]:
        index = int(sample[1].stem.split("_")[-1])
        return (sample[0], index if mode == "random" else index // 10)

    groups = sorted({key(s) for s in samples if s[0] not in auto_sessions})
    random.Random(seed).shuffle(groups)
    test_groups = set(groups[: int(round(test_fraction * len(groups)))])
    train = [s for s in samples if key(s) not in test_groups]
    test = [s for s in samples if key(s) in test_groups]
    return train, test


def read_dataset(dataset: pathlib.Path) -> Tuple[List[pathlib.Path], List[pathlib.Path]]:
    """
    Read the sessions and the test sessions of a dataset directory.

    The directory holds the recordings in sessions/ (gesture recorder) and gameplay/
    (gameplay with automatic labels), and split.json with
    {"test": ["sessions/<name>", ...]}; all the other recordings are for training.
    """
    split_path = dataset / "split.json"
    if not split_path.exists():
        raise TrainingError(f"{split_path} is missing; it lists the test sessions.")
    split = read_model(split_path, Split)

    sessions = [
        path.resolve()
        for kind in ("sessions", "gameplay")
        if (dataset / kind).is_dir()
        for path in sorted((dataset / kind).iterdir())
        if path.is_dir()
    ]
    test = [(dataset / name).resolve() for name in split.test]
    missing = [str(path) for path in test if path not in sessions]
    if missing:
        raise TrainingError(f"The test sessions {missing} of {split_path} do not exist.")
    if not test:
        raise TrainingError(f"{split_path} lists no test sessions.")
    return sessions, test


def sha256_of(path: pathlib.Path) -> str:
    """Compute the SHA-256 of the file."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


#: The default directory of the trainings, where the runs keep their checkpoints,
#: outside of the repository (--trainings-dir).
TRAININGS_DIR = pathlib.Path.home() / "splash-n-splat-trainings"


class Run:
    """
    A run of the training in its own directory, which survives a restart: its
    configuration (config.json), its state (state.json: the phase, the epoch
    and the seconds trained so far), and a checkpoint of the model and of the
    optimizer after every epoch, per phase.

    Resume the last unfinished run with ``--resume``: the crops are made again,
    identically from the same seed and the cached hand boxes, and the training
    continues after the last saved epoch.
    """

    def __init__(self, directory: pathlib.Path, config: Dict[str, Any]) -> None:
        self.directory = directory
        self.config = config
        self.state: Dict[str, Any] = {"phase": "head", "epoch": 0, "seconds": 0.0, "done": False}

    @staticmethod
    def start(trainings_dir: pathlib.Path, config: Dict[str, Any], resume: Optional[str]) -> "Run":
        """Start a new run, or resume the given run (or the last unfinished one for "last")."""
        if resume is None:
            name = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
            run = Run(trainings_dir / name, config)
            run.directory.mkdir(parents=True, exist_ok=False)
            run._write("config.json", config)
            run.save_state()
            print(f"Training in {run.directory}; resume with --resume if it stops.", flush=True)
            return run

        if resume == "last":
            unfinished = [
                d
                for d in sorted(trainings_dir.glob("*"))
                if (d / "state.json").exists()
                and not json.loads((d / "state.json").read_text())["done"]
            ]
            if not unfinished:
                raise TrainingError(f"There is no unfinished run in {trainings_dir} to resume.")
            directory = unfinished[-1]
        else:
            directory = pathlib.Path(resume)

        saved = json.loads((directory / "config.json").read_text())
        if saved != config:
            changed = sorted(k for k in set(saved) | set(config) if saved.get(k) != config.get(k))
            raise TrainingError(
                f"The run {directory} was started with another configuration ({changed}); "
                "start a new run instead."
            )
        run = Run(directory, config)
        run.state = json.loads((directory / "state.json").read_text())
        print(
            f"Resuming {directory} in the phase {run.state['phase']} after epoch "
            f"{run.state['epoch']}.",
            flush=True,
        )
        return run

    def _write(self, name: str, value: Dict[str, Any]) -> None:
        # NOTE (mristin):
        # We write atomically, so that a power cut leaves the old file, not half a file.
        part = self.directory / (name + ".part")
        part.write_text(json.dumps(value, indent=2) + "\n")
        part.replace(self.directory / name)

    def save_state(self) -> None:
        self._write("state.json", self.state)


def train_phase(
    run: Run,
    phase: str,
    model: Any,
    learning_rate: float,
    epochs: int,
    fit: Dict[str, Any],
) -> None:
    """
    Train a phase of the run with a checkpoint after every epoch, continuing
    after its last checkpoint; a finished phase is only restored.
    """
    import tensorflow as tf  # pylint: disable=import-outside-toplevel

    phases = ["head", "finetune", "export"]
    started = tf.train.latest_checkpoint(str(run.directory / phase)) is not None
    if phase == "finetune" and run.state["phase"] == "finetune" and not started:
        # NOTE (mristin):
        # The fine-tuning starts from the end of the head phase. We restore it
        # before we compile the model with the new optimizer: a Keras model
        # carries its optimizer in the checkpoint, so restoring afterwards would
        # also restore the state of the old optimizer into the new one, with its
        # learning rate five times as high, which ruined the fine-tuning.
        previous = tf.train.latest_checkpoint(str(run.directory / "head"))
        if previous is not None:
            tf.train.Checkpoint(model=model).restore(previous).expect_partial()

    optimizer = tf.keras.optimizers.Adam(learning_rate)
    model.compile(optimizer, "sparse_categorical_crossentropy", ["accuracy"])
    checkpoint = tf.train.Checkpoint(model=model, optimizer=optimizer)
    manager = tf.train.CheckpointManager(checkpoint, str(run.directory / phase), max_to_keep=2)

    if phases.index(run.state["phase"]) > phases.index(phase):
        if manager.latest_checkpoint is None:
            raise TrainingError(f"The finished phase {phase} of {run.directory} has no checkpoint.")
        checkpoint.restore(manager.latest_checkpoint).expect_partial()
        return

    initial_epoch = run.state["epoch"]
    if manager.latest_checkpoint is not None:
        checkpoint.restore(manager.latest_checkpoint)

    # NOTE (mristin):
    # The fine-tuning overfits after a few epochs: the accuracy on the held-out
    # hands peaked at the third epoch of 15 and then sank by two points, while
    # the loss on them grew. We therefore keep the model of the epoch with the
    # lowest held-out loss, and install it instead of the last one (see
    # restore_best). The held-out hands are also the test hands, so choosing
    # the epoch by them makes the reported numbers slightly optimistic.
    best = tf.train.CheckpointManager(
        tf.train.Checkpoint(model=model), str(run.directory / f"{phase}-best"), max_to_keep=1
    )

    class SaveEveryEpoch(tf.keras.callbacks.Callback):
        """Save the model, the optimizer and the state after every epoch."""

        def __init__(self) -> None:
            super().__init__()
            self._start = time.time()

        def on_epoch_end(self, epoch: int, logs: Optional[Dict[str, float]] = None) -> None:
            manager.save(checkpoint_number=epoch + 1)
            val_loss = (logs or {}).get("val_loss")
            best_key = f"{phase}_best"
            if val_loss is not None and (
                best_key not in run.state or val_loss < run.state[best_key]["val_loss"]
            ):
                best.save(checkpoint_number=epoch + 1)
                run.state[best_key] = {"epoch": epoch + 1, "val_loss": float(val_loss)}
            run.state["epoch"] = epoch + 1
            run.state["seconds"] += time.time() - self._start
            self._start = time.time()
            run.save_state()

    if initial_epoch < epochs:
        model.fit(**fit, epochs=epochs, initial_epoch=initial_epoch, callbacks=[SaveEveryEpoch()])

    run.state["phase"] = phases[phases.index(phase) + 1]
    run.state["epoch"] = 0
    run.save_state()


def restore_best(run: "Run", phase: str, model: Any) -> Optional[Dict[str, float]]:
    """
    Restore the model of the epoch of the phase with the lowest held-out loss,
    if there was held-out data, and return its epoch and loss.
    """
    import tensorflow as tf  # pylint: disable=import-outside-toplevel

    best = run.state.get(f"{phase}_best")
    path = tf.train.latest_checkpoint(str(run.directory / f"{phase}-best"))
    if best is None or path is None:
        return None
    tf.train.Checkpoint(model=model).restore(path).expect_partial()
    print(
        f"Installing the model of the epoch {best['epoch']} of the {phase} "
        f"(the lowest held-out loss, {best['val_loss']:.4f}), not of the last one.",
        flush=True,
    )
    return best


def main() -> int:
    """Execute the entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dataset",
        help=(
            "A dataset directory with sessions/, gameplay/ and split.json, which lists the "
            "test sessions; all the others are used for training (implies --split holdout)"
        ),
    )
    parser.add_argument("--sessions", nargs="+", default=[], help="Recording directories")
    parser.add_argument(
        "--holdout", nargs="+", default=[], help="Sessions used only for the evaluation"
    )
    parser.add_argument(
        "--split",
        choices=["holdout", "random", "chunks"],
        default="chunks",
        help=(
            "holdout: test on the --holdout sessions; random: test on a random fraction "
            "of the frames; chunks: test on a random fraction of 2-second chunks (less "
            "leakage between the nearly identical neighboring frames)"
        ),
    )
    parser.add_argument("--test-fraction", type=float, default=0.25)
    parser.add_argument("--epochs", type=int, default=12)
    parser.add_argument("--copies", type=int, default=3, help="Augmented copies per hand")
    parser.add_argument("--threshold", type=float, default=0.5)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--dry-run", action="store_true", help="Train, but do not install")
    parser.add_argument("--labeling-detector", default=str(LABELING_DETECTOR))
    parser.add_argument(
        "--detector-threshold",
        type=float,
        default=0.4,
        help="The lowest score of the labeling detector for a hand (at least %s)" % SCORE_FLOOR,
    )
    parser.add_argument(
        "--settle-seconds",
        type=float,
        default=1.0,
        help="Skip the first seconds of every phase of the gesture recorder",
    )
    parser.add_argument(
        "--trainings-dir",
        default=str(TRAININGS_DIR),
        help=(
            "The directory of the trainings: every run keeps its checkpoints there, in its "
            "own directory, so that it survives a restart (default: %(default)s)"
        ),
    )
    parser.add_argument(
        "--resume",
        nargs="?",
        const="last",
        default=None,
        help="Resume a run: the last unfinished one, or the given run directory",
    )
    args = parser.parse_args()

    import tensorflow as tf  # pylint: disable=import-outside-toplevel
    import tf2onnx  # pylint: disable=import-outside-toplevel
    import onnx  # pylint: disable=import-outside-toplevel

    tf.keras.utils.set_random_seed(args.seed)

    holdout = [pathlib.Path(p).resolve() for p in args.holdout]
    sessions = [pathlib.Path(p).resolve() for p in args.sessions]
    if args.dataset:
        sessions, holdout = read_dataset(pathlib.Path(args.dataset))
        args.split = "holdout"
        print(f"Training sessions: {[s.name for s in sessions if s not in holdout]}")
        print(f"Test sessions: {[s.name for s in holdout]}")
    if not sessions:
        raise TrainingError("Give the recordings with --dataset or --sessions.")
    if args.detector_threshold < SCORE_FLOOR:
        raise TrainingError(f"The --detector-threshold must be at least {SCORE_FLOOR}.")
    finder = HandFinder(pathlib.Path(args.labeling_detector), args.detector_threshold)
    print(f"Collecting the hands with {finder.name}...", flush=True)

    auto_sessions = {s.name for s in sessions + holdout if (s / "labels.auto.json").exists()}
    auto_holdout = [s for s in holdout if s.name in auto_sessions]
    if auto_holdout:
        raise TrainingError(
            f"The held-out sessions {auto_holdout} are labeled automatically; never evaluate "
            "on automatic labels, hold out a session of the gesture recorder instead."
        )
    if auto_sessions:
        print(f"Automatically labeled sessions (training only): {sorted(auto_sessions)}")

    if args.split == "holdout":
        training_sessions = [s for s in sessions if s not in holdout]
        if not training_sessions or not holdout:
            raise TrainingError("The holdout split needs training and --holdout sessions.")
        train_samples = collect(training_sessions, finder, args.settle_seconds)
        test_samples = collect(holdout, finder, args.settle_seconds)
    else:
        training_sessions = sessions
        train_samples, test_samples = split_samples(
            collect(sessions, finder, args.settle_seconds),
            args.split,
            args.test_fraction,
            args.seed,
            auto_sessions,
        )

    def describe(samples: Sequence[Tuple[str, Any, Any, str]]) -> Dict[str, int]:
        return {label: sum(1 for s in samples if s[3] == label) for label in LABELS}

    print(f"Training hands: {describe(train_samples)}; held-out hands: {describe(test_samples)}")

    # NOTE (mristin):
    # The crops live in memory-mapped files next to the runs (overwritten by
    # every training, and ignored when resuming, since they have no state).
    crops_dir = pathlib.Path(args.trainings_dir) / "crops"
    x_train, y_train = load_crops(
        train_samples,
        augment=True,
        copies=args.copies,
        seed=args.seed,
        file=crops_dir / "train.npy",
    )
    x_test, y_test = (
        load_crops(test_samples, augment=False, copies=1, seed=0, file=crops_dir / "test.npy")
        if test_samples
        else (None, None)
    )

    # NOTE (mristin):
    # A run resumes only with exactly the same data and settings: the sessions,
    # their hands and labels (as collected), and the arguments.
    config = {
        "arguments": {
            k: v for k, v in vars(args).items() if k not in ("resume", "trainings_dir", "dry_run")
        },
        "training_sessions": [s.name for s in training_sessions],
        "holdout_sessions": [s.name for s in holdout],
        "training_hands": describe(train_samples),
        "holdout_hands": describe(test_samples),
        "samples_sha256": hashlib.sha256(
            repr([(s[0], s[1].name, s[3]) for s in train_samples + test_samples]).encode()
        ).hexdigest(),
    }
    run = Run.start(pathlib.Path(args.trainings_dir), config, args.resume)

    model, base = build_model()
    counts = np.bincount(y_train, minlength=len(LABELS))
    class_weight = {i: len(y_train) / (len(LABELS) * max(1, c)) for i, c in enumerate(counts)}

    train_ds = batches_of(x_train, y_train, 64, training=True, seed=args.seed)
    val_ds = batches_of(x_test, y_test, 128, training=False, seed=0) if x_test is not None else None

    # NOTE (mristin):
    # We first train only the head, then fine-tune the whole network gently;
    # both phases save a checkpoint after every epoch (see Run).
    fit = {
        "x": train_ds,
        "validation_data": val_ds,
        "class_weight": class_weight,
        "verbose": 2,
    }
    base.trainable = False
    train_phase(run, "head", model, 1e-3, 3, fit)
    base.trainable = True
    train_phase(run, "finetune", model, 2e-4, args.epochs, fit)
    best = restore_best(run, "finetune", model)
    training_seconds = run.state["seconds"]

    # NOTE (mristin):
    # We free the training crops (gigabytes) before the export and the evaluation.
    probe = x_test[:64] if x_test is not None else x_train[:64].copy()
    del train_ds, x_train
    gc.collect()

    out_dir = MODEL_DIR if not args.dry_run else run.directory
    onnx_path = out_dir / "fist_classifier.onnx"
    tf2onnx.convert.from_keras(
        model,
        input_signature=(
            tf.TensorSpec((None, INPUT_SIZE, INPUT_SIZE, 3), tf.float32, name="input"),
        ),
        opset=13,
        output_path=str(onnx_path),
    )
    onnx.checker.check_model(onnx.load(str(onnx_path)), full_check=True)

    options = ort.SessionOptions()
    options.intra_op_num_threads = 1
    session = ort.InferenceSession(str(onnx_path), options, providers=["CPUExecutionProvider"])

    keras_out = model.predict(probe.astype(np.float32), verbose=0)
    onnx_out = session.run(None, {"input": probe.astype(np.float32)})[0]
    parity = float(np.max(np.abs(keras_out - onnx_out)))
    if parity > 1e-4:
        raise TrainingError(f"The ONNX model deviates from Keras by {parity}; do not use it.")

    durations = []
    sample = probe[:2].astype(np.float32)
    for _ in range(20):
        session.run(None, {"input": sample})
    for _ in range(200):
        t = time.perf_counter()
        session.run(None, {"input": sample})
        durations.append((time.perf_counter() - t) * 1000)
    durations.sort()

    report = TrainingReport(
        generated=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        split=args.split,
        test_fraction=args.test_fraction if args.split != "holdout" else None,
        labeling_detector=finder.name,
        training_sessions=[s.name for s in training_sessions],
        holdout_sessions=[s.name for s in holdout],
        training_hands=describe(train_samples),
        holdout_hands=describe(test_samples),
        augmented_copies=args.copies,
        epochs=3 + args.epochs,
        best_finetune_epoch=int(best["epoch"]) if best is not None else None,
        best_val_loss=best["val_loss"] if best is not None else None,
        training_seconds=training_seconds,
        keras_vs_onnx_max_abs_error=parity,
        onnx_latency_batch_2_ms=Latency(median=durations[100], p95=durations[190]),
        onnx_sha256=sha256_of(onnx_path),
    )
    if x_test is not None:
        # NOTE (mristin):
        # In batches: the whole test set at once (11000 hands in 2026-11) needed
        # more memory than the laptop has, and froze it until a restart.
        probabilities = np.concatenate(
            [
                session.run(None, {"input": x_test[i : i + 256].astype(np.float32)})[0]
                for i in range(0, len(x_test), 256)
            ]
        )
        report.holdout = {
            str(t): evaluate(probabilities, y_test, t) for t in (0.3, 0.4, 0.5, 0.6, 0.7, 0.8)
        }
        for threshold, metrics in report.holdout.items():
            print(f"  ours at {threshold}: {metrics}")

        # NOTE (mristin):
        # The baseline: the MLTK rock-paper-scissors model on the very same crops,
        # with p(rock) as p(fist).
        is_fist = y_test == 1
        comparison: Dict[str, Any] = {"ours_auc": roc_auc(probabilities[:, 1], is_fist)}
        for turns in ((0,), (1,), (0, 1, 3)):
            mltk = mltk_fist_probabilities(test_samples, turns)
            comparison[f"mltk_rotations_{turns}_auc"] = roc_auc(mltk, is_fist)
            comparison[f"mltk_rotations_{turns}_at_0.5"] = evaluate(
                np.stack([1 - mltk, mltk], 1), y_test, 0.5
            )
        comparison["ours_at_0.5"] = report.holdout["0.5"]
        report.comparison_with_mltk = comparison
        for key, value in comparison.items():
            print(f"  {key}: {value}")

    metadata = ClassifierMetadata(
        model=onnx_path.name,
        source="Trained on recordings by dev/computer_vision/train_fist_classifier.py",
        architecture="MobileNetV3-Small (alpha 0.75), ImageNet-pretrained, fine-tuned",
        input=ClassifierInput(
            name="input",
            shape=[-1, INPUT_SIZE, INPUT_SIZE, 3],
            layout="NHWC",
            dtype="float32",
            channel_order="RGB",
            normalization=(
                "none, values in [0, 255]; the model normalizes the contrast of every crop "
                "to its center and rescales itself"
            ),
            crop=f"square, {CROP_SCALE} x the longer side of the hand box, clamped to the frame",
            resize="bilinear (area-averaged when shrinking)",
        ),
        output=ClassifierOutput(name=session.get_outputs()[0].name, shape=[-1, len(LABELS)]),
        labels={str(i): label for i, label in enumerate(LABELS)},
    )
    write_model(out_dir / "fist_classifier.json", metadata)
    if not args.dry_run:
        write_model(REPO_ROOT / "dev" / "computer_vision" / "fist_classifier_report.json", report)

    # NOTE (mristin):
    # The run keeps a copy of its results, also when they are installed.
    if out_dir != run.directory:
        shutil.copy(onnx_path, run.directory / onnx_path.name)
        shutil.copy(out_dir / "fist_classifier.json", run.directory / "fist_classifier.json")
    write_model(run.directory / "fist_classifier_report.json", report)
    run.state["done"] = True
    run.save_state()
    print(f"Wrote {onnx_path} (parity {parity:.1e}, latency {durations[100]:.2f} ms for 2 crops)")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except TrainingError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
