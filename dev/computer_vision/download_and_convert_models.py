#!/usr/bin/env python3

"""
Download, verify, convert and validate the models of Splash 'n' Splat.

The game needs two models, both run with ONNX Runtime in C#:

1. The hand detector, YOLOX-Body-Head-Hand (nano) from the PINTO model zoo
   (Apache-2.0). We take the variant with the dynamic input shape and without
   the built-in post-processing, so that the game can choose the input
   resolution at runtime and apply its own non-maximum suppression.

2. The gesture classifier, rock_paper_scissors from the Silicon Labs MLTK (Zlib).
   It is a direct image classifier (84x84x1 grayscale crop -> rock, paper,
   scissor, _unknown_). The archive contains the original Keras model (.h5),
   a float32 TFLite and an int8-quantized TFLite. We convert the Keras model
   to a floating-point ONNX model with tf2onnx, and, for comparison,
   the int8 TFLite to ONNX as well.

We download every artifact only once into a cache, verify its SHA-256 and
record the source URLs and the hashes in a manifest. The script fails loudly
if anything does not match or does not validate.

Run it once after cloning (see README.md):

    venv/bin/python dev/computer_vision/download_and_convert_models.py
"""

import argparse
import dataclasses
import datetime
import hashlib
import io
import json
import os
import pathlib
import random
import shutil
import statistics
import sys
import tarfile
import time
import urllib.request
import zipfile
from typing import Any, Dict, List, Optional, Sequence, Tuple

REPO_ROOT = pathlib.Path(os.path.realpath(__file__)).parent.parent.parent

YOLOX_MODEL_DIR = REPO_ROOT / "scenes" / "hand_tracker" / "yolox" / "model"
GESTURE_MODEL_DIR = REPO_ROOT / "scenes" / "hand_tracker" / "gesture" / "model"
TEST_DATA_DIR = REPO_ROOT / "tests" / "SplashNSplat.Tests" / "data"

# NOTE (mristin):
# The classes of the hand detector, see the README of the model zoo entry.
YOLOX_CLASSES = ["body", "head", "hand"]
YOLOX_MEMBER = "yolox_n_body_head_hand_Nx3xHxW.onnx"
YOLOX_FIXED_MEMBER = "yolox_n_body_head_hand_0461_0.4428_1x3x256x320.onnx"

# NOTE (mristin):
# The order of the labels as stored in the model archive
# (rock_paper_scissors.tflite.summary.txt: "Classes: rock, paper, scissor, _unknown_").
GESTURE_CLASSES = ["rock", "paper", "scissor", "_unknown_"]
GESTURE_INPUT_SIZE = 84


@dataclasses.dataclass(frozen=True)
class Asset:
    """Represent a single downloadable upstream artifact."""

    name: str
    url: str
    sha256: str
    license: str
    note: str


PINTO_COMMIT = "286f03194bcbeef991f00054810f6b8d56d44955"
MLTK_COMMIT = "ee2a1fc32dbafa5a2e5af66c54f6b3b62c445f2a"
MLTK_ASSETS_COMMIT = "db459655f2c2a8dde34df34962d88dd0b1f6a9bf"

ASSETS = {
    "yolox": Asset(
        name="resources_n.tar.gz",
        # NOTE (mristin):
        # This is the URL from 426_YOLOX-Body-Head-Hand/download_n.sh. The bucket is
        # not versioned, hence we pin the hash.
        url=(
            "https://s3.ap-northeast-2.wasabisys.com/pinto-model-zoo/"
            "426_YOLOX-Body-Head-Hand/resources_n.tar.gz"
        ),
        sha256="04607eeaa3148ef82ccffd2b6fd9f7ef837467234600c06f3e65cf42bb6ae4f7",
        license="Apache-2.0",
        note="YOLOX-Body-Head-Hand nano, all input resolutions (252 MB)",
    ),
    "yolox_license": Asset(
        name="PINTO_426_LICENSE",
        url=(
            f"https://raw.githubusercontent.com/PINTO0309/PINTO_model_zoo/{PINTO_COMMIT}/"
            "426_YOLOX-Body-Head-Hand/LICENSE"
        ),
        sha256="cfd84da88aa611197e6597371ddaf5d59593bd4a7df768b6838d45b929ae951a",
        license="Apache-2.0",
        note="License of the YOLOX-Body-Head-Hand model",
    ),
    "mltk": Asset(
        name="rock_paper_scissors.mltk.zip",
        url=(
            f"https://github.com/SiliconLabs/mltk/raw/{MLTK_COMMIT}/"
            "mltk/models/siliconlabs/rock_paper_scissors.mltk.zip"
        ),
        sha256="675eebc1b1148563a7bf05fd04c7ffa5fc27d5278c8df5f0161c13fb55b32343",
        license="Zlib",
        note="MLTK rock_paper_scissors: Keras .h5, float32 and int8 TFLite",
    ),
    "mltk_license": Asset(
        name="MLTK_LICENSE.md",
        url=f"https://raw.githubusercontent.com/SiliconLabs/mltk/{MLTK_COMMIT}/LICENSE.md",
        sha256="52f7b1084ea81058d25143dcc3ddbfc1d87e86488ffbc77ef1812bd2674c80b3",
        license="Zlib",
        note="License of the Silicon Labs MLTK",
    ),
    "rps_dataset": Asset(
        name="rock_paper_scissors_v2.7z",
        url=(
            f"https://github.com/SiliconLabs/mltk_assets/raw/{MLTK_ASSETS_COMMIT}/"
            "datasets/rock_paper_scissors_v2.7z"
        ),
        # NOTE (mristin):
        # Upstream verifies SHA-1 77ED1793BE7871DCAA79D935B39BA4D23A28E2C3, see
        # mltk/datasets/image/rock_paper_scissors_v2.py. We checked that it matches.
        sha256="bf20c4ee4756b4126e6bb414845157cb553ca206f4b9a697bec4c0849c7e8b7b",
        license="Zlib",
        note="Rock/paper/scissors dataset v2, used only to validate the conversion",
    ),
}


class ConversionError(RuntimeError):
    """Signal that a step failed in a way the user has to act upon."""


def log(message: str) -> None:
    """Print a progress message."""
    print(message, flush=True)


def sha256_of(path: pathlib.Path) -> str:
    """Compute the SHA-256 of the file."""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(asset: Asset, cache_dir: pathlib.Path, manifest: Dict[str, Any]) -> pathlib.Path:
    """Download the asset into the cache unless it is already there, and verify it."""
    path = cache_dir / asset.name
    if not path.exists():
        log(f"Downloading {asset.url} ...")
        tmp_path = path.with_suffix(path.suffix + ".part")
        request = urllib.request.Request(
            asset.url, headers={"User-Agent": "splash-n-splat-model-setup"}
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response, tmp_path.open(
                "wb"
            ) as target:
                shutil.copyfileobj(response, target, length=1 << 20)
        except Exception as exception:
            tmp_path.unlink(missing_ok=True)
            raise ConversionError(
                f"Failed to download {asset.url}: {exception}. "
                "Check your network connection, or download the file by hand into "
                f"{path} and run the script again."
            ) from exception
        tmp_path.rename(path)
    else:
        log(f"Using the cached {path}")

    actual = sha256_of(path)
    if asset.sha256 and actual != asset.sha256:
        raise ConversionError(
            f"The SHA-256 of {path} is {actual}, but we expected {asset.sha256}. "
            "The upstream artifact changed or the download is corrupt. "
            f"Delete {path} and run again; if it persists, inspect the new upstream "
            "artifact before updating the hash in this script."
        )

    manifest["downloads"][asset.name] = {
        "url": asset.url,
        "sha256": actual,
        "pinned_sha256": asset.sha256 or None,
        "license": asset.license,
        "note": asset.note,
    }
    return path


def extract_yolox(archive: pathlib.Path, cache_dir: pathlib.Path) -> Dict[str, pathlib.Path]:
    """Extract the dynamic-shape and one fixed-shape YOLOX nano model from the archive."""
    result = {}
    with tarfile.open(archive, "r:gz") as tar:
        for member_name in (YOLOX_MEMBER, YOLOX_FIXED_MEMBER):
            target = cache_dir / member_name
            if not target.exists():
                try:
                    member = tar.getmember(member_name)
                except KeyError as exception:
                    raise ConversionError(
                        f"The archive {archive} does not contain {member_name}. "
                        "Inspect it with `tar tzf` and update YOLOX_MEMBER."
                    ) from exception
                if not member.isfile():
                    raise ConversionError(f"{member_name} in {archive} is not a regular file.")
                stream = tar.extractfile(member)
                assert stream is not None
                target.write_bytes(stream.read())
            result[member_name] = target
    return result


def extract_mltk(archive: pathlib.Path, cache_dir: pathlib.Path) -> Dict[str, pathlib.Path]:
    """Extract the Keras model, the TFLite models and their summaries."""
    wanted = [
        "rock_paper_scissors.h5",
        "rock_paper_scissors.tflite",
        "rock_paper_scissors.float32.tflite",
        "rock_paper_scissors.tflite.summary.txt",
        "rock_paper_scissors.h5.summary.txt",
    ]
    target_dir = cache_dir / "mltk"
    target_dir.mkdir(exist_ok=True)
    result = {}
    with zipfile.ZipFile(archive) as zip_file:
        names = set(zip_file.namelist())
        for name in wanted:
            if name not in names:
                raise ConversionError(
                    f"The MLTK archive {archive} does not contain {name}; "
                    f"it contains: {sorted(names)}"
                )
            target = target_dir / name
            target.write_bytes(zip_file.read(name))
            result[name] = target
    return result


def check_labels(summary_path: pathlib.Path) -> None:
    """Make sure the label order in the archive is the one we hard-code."""
    text = summary_path.read_text(encoding="utf-8")
    expected = "Classes: " + ", ".join(GESTURE_CLASSES)
    if expected not in text:
        raise ConversionError(
            f"Expected the line {expected!r} in {summary_path}, but it is missing. "
            "The label order changed; update GESTURE_CLASSES."
        )


def extract_dataset_samples(
    archive: pathlib.Path, per_class: int, seed: int
) -> Dict[str, List[Tuple[str, bytes]]]:
    """Read a deterministic random subset of the images of each class."""
    import py7zr  # pylint: disable=import-outside-toplevel

    with py7zr.SevenZipFile(archive, "r") as seven_zip:
        names = [name for name in seven_zip.getnames() if name.lower().endswith(".jpg")]

    chosen: Dict[str, List[str]] = {}
    rng = random.Random(seed)
    for label in GESTURE_CLASSES:
        candidates = sorted(name for name in names if f"/{label}/" in f"/{name}")
        if len(candidates) < per_class:
            raise ConversionError(
                f"Expected at least {per_class} images of {label} in {archive}, "
                f"got {len(candidates)}."
            )
        chosen[label] = rng.sample(candidates, per_class)

    wanted = {name for names_ in chosen.values() for name in names_}
    with py7zr.SevenZipFile(archive, "r") as seven_zip:
        contents = seven_zip.read(targets=list(wanted))

    return {
        label: [(name, contents[name].read()) for name in names_]
        for label, names_ in chosen.items()
    }


def mltk_preprocess(image_bytes: bytes) -> "Any":
    """
    Pre-process an image exactly as the MLTK did during the training.

    The MLTK ParallelImageDataGenerator loads the image with Keras' ``load_img``
    in the grayscale mode (PIL ``convert("L")``), resizes it to 84x84 with
    the bilinear interpolation, and standardizes each sample
    (``samplewise_center`` and ``samplewise_std_normalization``):
    ``x = (x - mean(x)) / (std(x) + 1e-6)``.
    """
    import numpy as np  # pylint: disable=import-outside-toplevel
    from PIL import Image  # pylint: disable=import-outside-toplevel

    image = Image.open(io.BytesIO(image_bytes)).convert("L")
    image = image.resize((GESTURE_INPUT_SIZE, GESTURE_INPUT_SIZE), Image.BILINEAR)
    x = np.asarray(image, dtype=np.float32)[:, :, None]
    x = x - np.mean(x, keepdims=True)
    x = x / (np.std(x, keepdims=True) + 1e-6)
    return x


def synthetic_inputs(count: int, seed: int) -> "Any":
    """Generate synthetic standardized inputs: noise, gradients and blobs."""
    import numpy as np  # pylint: disable=import-outside-toplevel

    rng = np.random.default_rng(seed)
    size = GESTURE_INPUT_SIZE
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    images = []
    for i in range(count):
        kind = i % 4
        if kind == 0:
            image = rng.uniform(0, 255, (size, size))
        elif kind == 1:
            angle = rng.uniform(0, np.pi)
            image = 127 + 127 * np.sin((np.cos(angle) * xx + np.sin(angle) * yy) / 9)
        elif kind == 2:
            cx, cy, r = rng.uniform(20, 64), rng.uniform(20, 64), rng.uniform(10, 30)
            image = np.where((xx - cx) ** 2 + (yy - cy) ** 2 < r * r, 220.0, 60.0)
            image = image + rng.normal(0, 8, (size, size))
        else:
            image = xx * 3 + rng.normal(0, 20, (size, size))
        x = image.astype(np.float32)[:, :, None]
        x = (x - x.mean()) / (x.std() + 1e-6)
        images.append(x)
    return np.stack(images).astype(np.float32)


class TfliteRunner:
    """Run a TFLite model one sample at a time."""

    def __init__(self, path: pathlib.Path) -> None:
        import tensorflow as tf  # pylint: disable=import-outside-toplevel

        self.interpreter = tf.lite.Interpreter(model_path=str(path))
        self.interpreter.allocate_tensors()
        self.input = self.interpreter.get_input_details()[0]
        self.output = self.interpreter.get_output_details()[0]

    def __call__(self, batch: "Any") -> "Any":
        import numpy as np  # pylint: disable=import-outside-toplevel

        outputs = []
        for sample in batch:
            self.interpreter.set_tensor(self.input["index"], sample[None].astype(np.float32))
            self.interpreter.invoke()
            outputs.append(self.interpreter.get_tensor(self.output["index"])[0].copy())
        return np.stack(outputs)


class OnnxRunner:
    """Run an ONNX model with the CPU execution provider."""

    def __init__(self, path: pathlib.Path, threads: int = 1) -> None:
        import onnxruntime as ort  # pylint: disable=import-outside-toplevel

        options = ort.SessionOptions()
        options.intra_op_num_threads = threads
        options.inter_op_num_threads = 1
        self.session = ort.InferenceSession(str(path), options, providers=["CPUExecutionProvider"])
        self.input_name = self.session.get_inputs()[0].name

    def __call__(self, batch: "Any") -> "Any":
        import numpy as np  # pylint: disable=import-outside-toplevel

        outputs = [
            self.session.run(None, {self.input_name: sample[None].astype(np.float32)})[0][0]
            for sample in batch
        ]
        return np.stack(outputs)


def convert_keras_to_onnx(h5_path: pathlib.Path, onnx_path: pathlib.Path) -> "Any":
    """Convert the Keras model to a float32 ONNX model; return the Keras model."""
    import tensorflow as tf  # pylint: disable=import-outside-toplevel
    import tf2onnx  # pylint: disable=import-outside-toplevel

    keras_model = tf.keras.models.load_model(str(h5_path), compile=False)
    shape = tuple(keras_model.inputs[0].shape)
    if shape[1:] != (GESTURE_INPUT_SIZE, GESTURE_INPUT_SIZE, 1):
        raise ConversionError(
            f"Expected the Keras input of shape (None, 84, 84, 1), but got {shape}. "
            "The archive changed; inspect rock_paper_scissors.h5.summary.txt."
        )

    spec = (
        tf.TensorSpec((None, GESTURE_INPUT_SIZE, GESTURE_INPUT_SIZE, 1), tf.float32, name="input"),
    )
    try:
        tf2onnx.convert.from_keras(
            keras_model, input_signature=spec, opset=13, output_path=str(onnx_path)
        )
    except Exception as exception:
        raise ConversionError(
            f"tf2onnx failed to convert {h5_path}: {exception}. "
            "Make sure the pinned versions of dev/computer_vision/requirements.txt are installed "
            "(tf2onnx 1.16.1 supports TensorFlow up to 2.15)."
        ) from exception
    return keras_model


def convert_tflite_to_onnx(tflite_path: pathlib.Path, onnx_path: pathlib.Path) -> Optional[str]:
    """Convert the int8 TFLite model to ONNX; return an error message on failure."""
    import tf2onnx  # pylint: disable=import-outside-toplevel

    try:
        tf2onnx.convert.from_tflite(str(tflite_path), opset=13, output_path=str(onnx_path))
    except Exception as exception:  # pylint: disable=broad-except
        onnx_path.unlink(missing_ok=True)
        return f"{type(exception).__name__}: {exception}"
    return None


def check_onnx(path: pathlib.Path) -> Dict[str, Any]:
    """Check the model with onnx.checker and describe its inputs and outputs."""
    import onnx  # pylint: disable=import-outside-toplevel
    import onnxruntime as ort  # pylint: disable=import-outside-toplevel

    model = onnx.load(str(path))
    try:
        onnx.checker.check_model(model, full_check=True)
    except Exception as exception:
        raise ConversionError(f"onnx.checker rejected {path}: {exception}") from exception

    session = ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])

    def describe(values: Sequence[Any]) -> List[Dict[str, Any]]:
        return [{"name": v.name, "shape": list(v.shape), "type": v.type} for v in values]

    return {
        "file": path.name,
        "sha256": sha256_of(path),
        "size_bytes": path.stat().st_size,
        "opset": [{"domain": o.domain, "version": o.version} for o in model.opset_import],
        "operators": sorted({node.op_type for node in model.graph.node}),
        "inputs": describe(session.get_inputs()),
        "outputs": describe(session.get_outputs()),
    }


def compare(name_a: str, out_a: "Any", name_b: str, out_b: "Any") -> Dict[str, Any]:
    """Compare two sets of class probabilities."""
    import numpy as np  # pylint: disable=import-outside-toplevel

    return {
        "a": name_a,
        "b": name_b,
        "max_abs_error": float(np.max(np.abs(out_a - out_b))),
        "mean_abs_error": float(np.mean(np.abs(out_a - out_b))),
        "class_agreement": float(np.mean(np.argmax(out_a, 1) == np.argmax(out_b, 1))),
    }


def benchmark(runner: Any, sample: "Any", repeats: int = 300) -> Dict[str, float]:
    """Measure the latency of a single-sample inference in milliseconds."""
    for _ in range(20):
        runner(sample[None])
    durations = []
    for _ in range(repeats):
        start = time.perf_counter()
        runner(sample[None])
        durations.append((time.perf_counter() - start) * 1000.0)
    durations.sort()
    return {
        "median_ms": statistics.median(durations),
        "p95_ms": durations[int(0.95 * (len(durations) - 1))],
    }


def validate_yolox(
    dynamic_path: pathlib.Path, fixed_path: pathlib.Path, report: Dict[str, Any]
) -> None:
    """Check the YOLOX models, run a dummy inference and compare dynamic vs. fixed."""
    import numpy as np  # pylint: disable=import-outside-toplevel

    report["yolox"] = {"dynamic": check_onnx(dynamic_path), "fixed": check_onnx(fixed_path)}

    dynamic = OnnxRunner(dynamic_path, threads=2)
    fixed = OnnxRunner(fixed_path, threads=2)

    rng = np.random.default_rng(0)
    x = rng.uniform(0, 255, (1, 3, 256, 320)).astype(np.float32)
    out_dynamic = dynamic.session.run(None, {dynamic.input_name: x})[0]
    out_fixed = fixed.session.run(None, {fixed.input_name: x})[0]

    expected_rows = sum((256 // s) * (320 // s) for s in (8, 16, 32))
    if out_dynamic.shape != (1, expected_rows, 5 + len(YOLOX_CLASSES)):
        raise ConversionError(
            f"Expected the YOLOX output of shape (1, {expected_rows}, 8) for an input of "
            f"256x320, but got {out_dynamic.shape}."
        )

    timings = {}
    for height, width in ((128, 160), (192, 256), (256, 320), (320, 320)):
        sample = rng.uniform(0, 255, (3, height, width)).astype(np.float32)
        timings[f"{width}x{height}"] = benchmark(dynamic, sample, repeats=60)

    report["yolox"]["dummy_inference"] = {
        "input_shape": list(x.shape),
        "output_shape": list(out_dynamic.shape),
        "max_abs_difference_dynamic_vs_fixed": float(np.max(np.abs(out_dynamic - out_fixed))),
        "latency_2_threads": timings,
    }


def validate_gesture(
    keras_model: Any,
    paths: Dict[str, pathlib.Path],
    float_onnx: pathlib.Path,
    int8_onnx: Optional[pathlib.Path],
    samples: Dict[str, List[Tuple[str, bytes]]],
    report: Dict[str, Any],
) -> None:
    """Compare Keras, TFLite and ONNX on synthetic and real inputs."""
    import numpy as np  # pylint: disable=import-outside-toplevel

    real_x = np.stack(
        [mltk_preprocess(data) for label in GESTURE_CLASSES for _, data in samples[label]]
    ).astype(np.float32)
    real_y = np.array(
        [index for index, label in enumerate(GESTURE_CLASSES) for _ in samples[label]]
    )
    synthetic_x = synthetic_inputs(16, seed=0)

    runners: Dict[str, Any] = {
        "keras": lambda batch: keras_model.predict(batch, verbose=0),
        "tflite_float32": TfliteRunner(paths["rock_paper_scissors.float32.tflite"]),
        "tflite_int8": TfliteRunner(paths["rock_paper_scissors.tflite"]),
        "onnx_float32": OnnxRunner(float_onnx),
    }
    if int8_onnx is not None:
        runners["onnx_int8"] = OnnxRunner(int8_onnx)

    outputs = {
        name: {"real": runner(real_x), "synthetic": runner(synthetic_x)}
        for name, runner in runners.items()
    }

    pairs = [("keras", "onnx_float32"), ("tflite_float32", "onnx_float32")]
    if int8_onnx is not None:
        pairs += [("tflite_int8", "onnx_int8"), ("onnx_float32", "onnx_int8")]

    comparisons = []
    for a, b in pairs:
        for subset in ("real", "synthetic"):
            entry = compare(a, outputs[a][subset], b, outputs[b][subset])
            entry["subset"] = subset
            comparisons.append(entry)

    accuracy = {
        name: float(np.mean(np.argmax(out["real"], 1) == real_y)) for name, out in outputs.items()
    }

    speed = {name: benchmark(runners[name], real_x[0]) for name in runners if "onnx" in name}

    report["gesture"]["validation"] = {
        "real_samples": int(len(real_y)),
        "synthetic_samples": int(len(synthetic_x)),
        "comparisons": comparisons,
        "accuracy_on_real_samples": accuracy,
        "onnx_latency_1_thread": speed,
    }

    for entry in comparisons:
        if entry["a"] == "keras" and entry["b"] == "onnx_float32":
            if entry["max_abs_error"] > 1e-4 or entry["class_agreement"] < 1.0:
                raise ConversionError(
                    "The float32 ONNX model does not reproduce the Keras model: "
                    f"{entry}. Do not use it."
                )


def write_test_samples(
    samples: Dict[str, List[Tuple[str, bytes]]], keras_model: Any, per_class: int
) -> None:
    """Write a few dataset images with the Keras reference outputs for the C# tests."""
    import numpy as np  # pylint: disable=import-outside-toplevel
    from PIL import Image  # pylint: disable=import-outside-toplevel

    target_dir = TEST_DATA_DIR / "rps"
    target_dir.mkdir(parents=True, exist_ok=True)
    references = []
    for label in GESTURE_CLASSES:
        for index, (source, data) in enumerate(samples[label][:per_class]):
            file_name = f"{label.strip('_')}_{index}.png"
            Image.open(io.BytesIO(data)).convert("L").save(target_dir / file_name)
            x = mltk_preprocess(data)[None]
            probabilities = keras_model.predict(x, verbose=0)[0]
            references.append(
                {
                    "file": file_name,
                    "source": source,
                    "label": label,
                    "keras_probabilities": [float(v) for v in probabilities],
                    "keras_argmax": int(np.argmax(probabilities)),
                }
            )
    (target_dir / "references.json").write_text(
        json.dumps(references, indent=2) + "\n", encoding="utf-8"
    )


def gesture_metadata(onnx_info: Dict[str, Any], variant: str) -> Dict[str, Any]:
    """Describe how to feed the gesture classifier."""
    return {
        "model": onnx_info["file"],
        "variant": variant,
        "source": "Silicon Labs MLTK rock_paper_scissors (version 1)",
        "license": "Zlib",
        "input": {
            "name": onnx_info["inputs"][0]["name"],
            "shape": [-1, GESTURE_INPUT_SIZE, GESTURE_INPUT_SIZE, 1],
            "layout": "NHWC",
            "dtype": "float32",
            "channels": "grayscale (1 channel)",
            "grayscale_conversion": "PIL 'L' (ITU-R 601-2 luma): L = R*299/1000 + G*587/1000 + B*114/1000",
            "resize": "bilinear to 84x84 (the training images were 96x96)",
            "normalization": "per sample: x = (x - mean(x)) / (std(x) + 1e-6), x in [0, 255] before",
            "quantization": (
                "none, float32 throughout"
                if variant == "float32"
                else "the model quantizes the float input itself (QuantizeLinear)"
            ),
        },
        "output": {
            "name": onnx_info["outputs"][0]["name"],
            "shape": [-1, len(GESTURE_CLASSES)],
            "dtype": "float32",
            "meaning": "class probabilities (softmax is part of the model)",
        },
        "labels": {str(index): label for index, label in enumerate(GESTURE_CLASSES)},
        "game_mapping": {"rock": "FIST", "paper": "OPEN", "scissor": "OTHER", "_unknown_": "OTHER"},
        "training_augmentation": {
            "rotation_range_degrees": 15,
            "horizontal_flip": True,
            "vertical_flip": True,
            "note": "The training photos show hands from above; see README for the domain gap.",
        },
    }


def yolox_metadata(onnx_info: Dict[str, Any]) -> Dict[str, Any]:
    """Describe how to feed the hand detector and decode its output."""
    return {
        "model": onnx_info["file"],
        "source": "PINTO model zoo 426_YOLOX-Body-Head-Hand, nano, epoch 461, mAP 0.4428",
        "license": "Apache-2.0",
        "input": {
            "name": onnx_info["inputs"][0]["name"],
            "shape": ["N", 3, "H", "W"],
            "layout": "NCHW",
            "dtype": "float32",
            "channel_order": "BGR",
            "normalization": "none, values in [0, 255]",
            "resize": "letterbox: keep the aspect ratio, pad bottom/right with 114",
            "constraint": "H and W must be multiples of 32",
        },
        "output": {
            "name": onnx_info["outputs"][0]["name"],
            "shape": ["N", "sum over strides 8, 16, 32 of (H/s)*(W/s)", 8],
            "row": "cx, cy, w, h (raw, grid-relative), objectness, p(body), p(head), p(hand)",
            "decode": "cx = (raw + grid_x) * stride; w = exp(raw_w) * stride; "
            "score = objectness * p(class); sigmoid already applied",
            "nms": "not included; apply it per class",
        },
        "labels": {str(index): label for index, label in enumerate(YOLOX_CLASSES)},
    }


def main() -> int:
    """Execute the entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--cache-dir",
        default=str(REPO_ROOT / ".cache" / "models"),
        help="Where to keep the downloads between the runs",
    )
    parser.add_argument(
        "--samples-per-class",
        type=int,
        default=100,
        help="How many real dataset images per class to use for the validation",
    )
    args = parser.parse_args()

    try:
        import numpy  # pylint: disable=import-outside-toplevel,unused-import
        import onnx  # pylint: disable=import-outside-toplevel,unused-import
        import onnxruntime  # pylint: disable=import-outside-toplevel,unused-import
        import tensorflow  # pylint: disable=import-outside-toplevel,unused-import
        import tf2onnx  # pylint: disable=import-outside-toplevel,unused-import
    except ImportError as exception:
        print(
            f"A Python dependency is missing: {exception}. Install the pinned tools with:\n"
            "  python3 -m venv venv && touch venv/.gdignore\n"
            "  venv/bin/pip install -r dev/computer_vision/requirements.txt",
            file=sys.stderr,
        )
        return 1

    cache_dir = pathlib.Path(args.cache_dir)
    cache_dir.mkdir(parents=True, exist_ok=True)
    YOLOX_MODEL_DIR.mkdir(parents=True, exist_ok=True)
    GESTURE_MODEL_DIR.mkdir(parents=True, exist_ok=True)

    manifest: Dict[str, Any] = {
        "generated": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "downloads": {},
        "outputs": {},
    }
    report: Dict[str, Any] = {"gesture": {}}

    try:
        # Hand detector
        archive = download(ASSETS["yolox"], cache_dir, manifest)
        license_path = download(ASSETS["yolox_license"], cache_dir, manifest)
        yolox_paths = extract_yolox(archive, cache_dir)
        log("Validating the hand detector...")
        validate_yolox(yolox_paths[YOLOX_MEMBER], yolox_paths[YOLOX_FIXED_MEMBER], report)
        shutil.copyfile(yolox_paths[YOLOX_MEMBER], YOLOX_MODEL_DIR / YOLOX_MEMBER)
        shutil.copyfile(license_path, YOLOX_MODEL_DIR / "LICENSE")
        (YOLOX_MODEL_DIR / "yolox_n_body_head_hand.json").write_text(
            json.dumps(yolox_metadata(report["yolox"]["dynamic"]), indent=2) + "\n",
            encoding="utf-8",
        )

        # Gesture classifier
        mltk_archive = download(ASSETS["mltk"], cache_dir, manifest)
        mltk_license = download(ASSETS["mltk_license"], cache_dir, manifest)
        dataset = download(ASSETS["rps_dataset"], cache_dir, manifest)
        mltk_paths = extract_mltk(mltk_archive, cache_dir)
        check_labels(mltk_paths["rock_paper_scissors.tflite.summary.txt"])

        float_onnx = GESTURE_MODEL_DIR / "rock_paper_scissors_float32.onnx"
        log("Converting the Keras model to ONNX...")
        keras_model = convert_keras_to_onnx(mltk_paths["rock_paper_scissors.h5"], float_onnx)
        report["gesture"]["float32"] = check_onnx(float_onnx)

        int8_onnx: Optional[pathlib.Path] = cache_dir / "rock_paper_scissors_int8.onnx"
        assert int8_onnx is not None
        log("Converting the int8 TFLite model to ONNX (for comparison only)...")
        error = convert_tflite_to_onnx(mltk_paths["rock_paper_scissors.tflite"], int8_onnx)
        if error is not None:
            log(f"WARNING: the int8 TFLite model could not be converted: {error}")
            report["gesture"]["int8_conversion_error"] = error
            int8_onnx = None
        else:
            report["gesture"]["int8"] = check_onnx(int8_onnx)

        log("Validating the gesture classifier...")
        samples = extract_dataset_samples(dataset, args.samples_per_class, seed=42)
        validate_gesture(keras_model, mltk_paths, float_onnx, int8_onnx, samples, report)
        write_test_samples(samples, keras_model, per_class=3)

        shutil.copyfile(mltk_license, GESTURE_MODEL_DIR / "LICENSE.md")
        (GESTURE_MODEL_DIR / "rock_paper_scissors.json").write_text(
            json.dumps(gesture_metadata(report["gesture"]["float32"], "float32"), indent=2) + "\n",
            encoding="utf-8",
        )
    except ConversionError as exception:
        print(f"ERROR: {exception}", file=sys.stderr)
        return 1

    for path in (
        YOLOX_MODEL_DIR / YOLOX_MEMBER,
        GESTURE_MODEL_DIR / "rock_paper_scissors_float32.onnx",
    ):
        manifest["outputs"][str(path.relative_to(REPO_ROOT))] = {"sha256": sha256_of(path)}

    (REPO_ROOT / "dev" / "computer_vision" / "models_manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    (REPO_ROOT / "dev" / "computer_vision" / "models_validation_report.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )

    validation = report["gesture"]["validation"]
    log("")
    log("Summary")
    log("=======")
    for entry in validation["comparisons"]:
        log(
            f"  {entry['a']:>15} vs {entry['b']:<13} ({entry['subset']:>9}): "
            f"max abs error {entry['max_abs_error']:.2e}, "
            f"class agreement {100 * entry['class_agreement']:.1f}%"
        )
    for name, accuracy in validation["accuracy_on_real_samples"].items():
        log(f"  accuracy of {name} on {validation['real_samples']} dataset images: {accuracy:.3f}")
    for name, timing in validation["onnx_latency_1_thread"].items():
        log(f"  {name}: median {timing['median_ms']:.3f} ms, p95 {timing['p95_ms']:.3f} ms")
    for size, timing in report["yolox"]["dummy_inference"]["latency_2_threads"].items():
        log(f"  YOLOX {size}: median {timing['median_ms']:.1f} ms, p95 {timing['p95_ms']:.1f} ms")
    log("")
    log(
        "Wrote dev/computer_vision/models_manifest.json and dev/computer_vision/models_validation_report.json."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
