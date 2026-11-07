"""
Define the JSON files of the recordings, the dataset and the trained models.

We read and write all of them through these pydantic models, so that a file
which does not follow the format fails early with a clear message instead of
a KeyError deep in a training.

The frame metadata is written by C# (the gesture recorder, the gameplay
recording and the vision smoke test, see scenes/), the events by GDScript
(scenes/game/game.gd); keep these models in sync with them.
"""

import pathlib
from typing import Annotated, Dict, List, Literal, Optional, TypeVar, Union

from pydantic import BaseModel, ConfigDict, Field, RootModel, TypeAdapter

#: A box as [x1, y1, x2, y2] in pixels of the (not mirrored) frame.
Box = Annotated[List[float], Field(min_length=4, max_length=4)]

#: A box with the score of the detector: x1, y1, x2, y2, score.
ScoredBox = Annotated[List[float], Field(min_length=5, max_length=5)]

#: The labels of the fist classifier.
HandLabel = Literal["fist", "nonfist"]


class _Strict(BaseModel):
    """Refuse the unknown fields, so that the format can not drift unnoticed."""

    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class TrackedHand(_Strict):
    """A hand which the game tracked when the frame was recorded."""

    id: int
    box: Box
    score: float
    confirmed: bool

    # NOTE (mristin):
    # The gameplay recording and the smoke test also record the state of
    # the vision; the gesture recorder does not.
    velocity: Optional[Annotated[List[float], Field(min_length=2, max_length=2)]] = None
    classified: Optional[bool] = None
    open: Optional[float] = None
    fist: Optional[float] = None
    other: Optional[float] = None
    gesture: Optional[str] = None
    armed: Optional[bool] = None


class FrameMeta(_Strict):
    """
    The metadata of a recorded frame (``frame_NNNNN.json`` next to the image).

    The label is either ``fist`` or ``nonfist`` for all the hands of the frame,
    ``left=...,right=...`` for the hands on the left and the right half of
    the mirrored screen, ``open`` or ``other`` (early recordings), or
    ``gameplay`` (labeled per hand in labels.auto.json).
    """

    label: str = ""
    timestamp: float
    width: int = 640
    height: int = 480
    hands: List[TrackedHand] = []
    mirrored_sides: Optional[bool] = None

    # NOTE (mristin):
    # Only in the dumps of the vision smoke test.
    frame_timestamp: Optional[float] = None
    level: Optional[str] = None


class AimedHand(_Strict):
    """Where a hand aimed, in pixels of the 1920x1080 viewport."""

    hand_id: int
    x: float
    y: float
    over_bear: bool


class _Event(_Strict):
    """An event of the gameplay; ``t`` is on the clock of the frame timestamps."""

    t: float
    state: str


class AimsEvent(_Event):
    """Where all the hands aimed, logged ten times a second."""

    type: Literal["aims"]
    hands: List[AimedHand]


class ShotEvent(_Event):
    """A throw of a hand (-1 for a scripted throw)."""

    type: Literal["shot"]
    hand_id: int
    x: float
    y: float


class ResultEvent(_Event):
    """
    What the throw of a hand hit.

    A ``thrower`` is a penguin or a snowy owl which crosses the screen, a
    ``kitten`` must not be hit, and a ``booster`` is a balloon with a booster.
    """

    type: Literal["result"]
    hand_id: int
    what: Literal["bear", "snowball", "miss", "orca", "thrower", "kitten", "booster"]


class DodgeEvent(_Event):
    """A snowball which flew at a head of a player, who moved away in time."""

    type: Literal["dodge"]
    x: float
    y: float


Event = Annotated[Union[AimsEvent, ShotEvent, ResultEvent, DodgeEvent], Field(discriminator="type")]
_EVENT = TypeAdapter(Event)


class AutoLabel(_Strict):
    """A hand labeled automatically by auto_label_gameplay.py."""

    box: Box
    label: HandLabel
    reason: str
    p_fist: float


class AutoLabels(RootModel[Dict[str, List[AutoLabel]]]):
    """The automatic labels of a gameplay recording by frame file name (labels.auto.json)."""


class ReviewedHand(_Strict):
    """
    A hand of a gameplay recording whose automatic label we corrected by eye:
    the new label, or None to exclude the hand (e.g., no hand, or unclear).
    """

    box: Box
    #: None (or missing) excludes the hand.
    label: Optional[HandLabel] = None
    note: str


class ReviewedHands(RootModel[Dict[str, List[ReviewedHand]]]):
    """
    The corrected automatic labels of a gameplay recording by frame file name
    (labels.reviewed.json), made with review_hands.py; the training applies
    them over labels.auto.json.
    """


class ReviewedPhase(_Strict):
    """
    A phase of a session whose label we corrected by eye, from frame ``first``
    to frame ``last`` (file names, inclusive).

    The ``label`` replaces the label of the frames (e.g., when a child showed
    open hands while asked for fists); None excludes the frames (e.g., when the
    hands were mixed or unclear).
    """

    first: str
    last: str
    #: None (or missing) excludes the frames.
    label: Optional[str] = None
    note: str


class LabelReview(_Strict):
    """
    The corrected labels of a session of the gesture recorder (labels.review.json),
    made with dev/computer_vision/review_labels.py; the frame files stay as recorded.
    """

    comment: Optional[str] = Field(default=None, alias="_comment")
    model: str
    phases: List[ReviewedPhase]


class HandCache(RootModel[Dict[str, List[Box]]]):
    """The hands found by the labeling detector by frame file name (hands.<model>.<t>.json)."""


class ScoredHandCache(RootModel[Dict[str, List[ScoredBox]]]):
    """
    The hands found by the labeling detector, with their scores, by frame file
    name (scored_hands.<model>.json); the training filters them by the score,
    so that one cache serves every threshold.
    """


class Split(_Strict):
    """The split of a dataset (split.json): the test sessions; all others are for training."""

    comment: Optional[str] = Field(default=None, alias="_comment")
    test: List[str]


class SessionSummary(_Strict):
    """A recording in the manifest of a dataset."""

    kind: Literal["sessions", "gameplay"]
    frames: int
    labels: Dict[str, int]


class DatasetManifest(_Strict):
    """The manifest of a dataset (manifest.json): the recordings and the hash of each file."""

    recordings: Dict[str, SessionSummary]
    files: Dict[str, str]


class Metrics(_Strict):
    """The per-crop rates of a fist classifier at a threshold."""

    fist_recall: float
    nonfist_recall: float
    nonfist_as_fist: float
    accuracy: float
    count_fist: int
    count_nonfist: int


class Latency(_Strict):
    median: float
    p95: float


class TrainingReport(_Strict):
    """The report of train_fist_classifier.py (fist_classifier_report.json)."""

    generated: str
    split: str
    test_fraction: Optional[float] = None
    labeling_detector: str
    training_sessions: List[str]
    holdout_sessions: List[str]
    training_hands: Dict[str, int]
    holdout_hands: Dict[str, int]
    augmented_copies: int
    epochs: int
    #: The epoch of the fine-tuning which we installed: the one with the lowest
    #: loss on the held-out hands (None: the last one, as before 2026-11-07).
    best_finetune_epoch: Optional[int] = None
    best_val_loss: Optional[float] = None
    training_seconds: float
    #: None if not checked (the run of 2026-11-06 froze the laptop before the check).
    keras_vs_onnx_max_abs_error: Optional[float]
    onnx_latency_batch_2_ms: Latency
    onnx_sha256: str
    holdout: Dict[str, Metrics] = {}
    comparison_with_mltk: Dict[str, Union[float, Metrics]] = {}


class ClassifierInput(_Strict):
    name: str
    shape: List[int]
    layout: str
    dtype: str
    channel_order: str
    normalization: str
    crop: str
    resize: str


class ClassifierOutput(_Strict):
    name: str
    shape: List[int]


class ClassifierMetadata(_Strict):
    """How to feed the fist classifier (fist_classifier.json next to the model)."""

    model: str
    source: str
    architecture: str
    input: ClassifierInput
    output: ClassifierOutput
    labels: Dict[str, str]


ModelT = TypeVar("ModelT", bound=BaseModel)


def read_model(path: pathlib.Path, model: type[ModelT]) -> ModelT:
    """Read and validate a JSON file."""
    return model.model_validate_json(path.read_text(encoding="utf-8"))


def write_model(path: pathlib.Path, value: BaseModel) -> None:
    """Write a JSON file, with the aliases (e.g., ``_comment``) and without the unset optionals."""
    path.write_text(
        value.model_dump_json(indent=2, by_alias=True, exclude_none=True) + "\n",
        encoding="utf-8",
    )


def read_events(
    path: pathlib.Path,
) -> List[Union[AimsEvent, ShotEvent, ResultEvent, DodgeEvent]]:
    """Read and validate the events of a gameplay recording (events.jsonl)."""
    events = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if line.strip():
            try:
                events.append(_EVENT.validate_json(line))
            except ValueError as exception:
                raise ValueError(f"{path}:{number}: {exception}") from exception
    return events
