#!/usr/bin/env python3

"""
Download the large YOLOX hand detector which labels the training recordings.

The game runs YOLOX nano, which is fast but misses some hands (blurred, very near
or far). For preparing the training data of the fist classifier, speed does not
matter, so dev/computer_vision/train_fist_classifier.py finds the hands with the medium model
(mAP 0.5263 vs. 0.4428 of nano) at the full camera resolution.

PINTO ships the model only in a 7 GB archive with all the input resolutions.
We stream the archive and stop as soon as we have extracted the one model, so
nothing but the model is stored. This is a setup step for training only; the
game does not need it.

    venv/bin/python dev/computer_vision/download_labeling_detector.py
"""

import argparse
import hashlib
import json
import pathlib
import sys
import tarfile
import urllib.request

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
URL = (
    "https://s3.ap-northeast-2.wasabisys.com/pinto-model-zoo/"
    "426_YOLOX-Body-Head-Hand/resources_m.tar.gz"
)
MEMBER = "yolox_m_body_head_hand_post_0299_0.5263_1x3x480x640.onnx"


def main() -> int:
    """Execute the entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", default=str(REPO_ROOT / ".cache" / "models"))
    args = parser.parse_args()

    target = pathlib.Path(args.cache_dir) / MEMBER
    if target.exists():
        print(f"Already there: {target}")
        return 0

    target.parent.mkdir(parents=True, exist_ok=True)
    print(f"Streaming {URL} until {MEMBER} ...", flush=True)
    request = urllib.request.Request(URL, headers={"User-Agent": "splash-n-splat-model-setup"})
    seen = []
    with urllib.request.urlopen(request, timeout=60) as response:
        with tarfile.open(fileobj=response, mode="r|gz") as tar:
            for member in tar:
                seen.append(member.name)
                if pathlib.PurePosixPath(member.name).name != MEMBER:
                    continue
                stream = tar.extractfile(member)
                assert stream is not None
                part = target.with_suffix(".part")
                part.write_bytes(stream.read())
                part.rename(target)
                break

    if not target.exists():
        print(
            f"ERROR: {MEMBER} is not in {URL}. The archive contained, e.g.: {seen[:20]}",
            file=sys.stderr,
        )
        return 1

    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    record = {"url": URL, "member": MEMBER, "sha256": digest, "license": "Apache-2.0"}
    target.with_suffix(".json").write_text(json.dumps(record, indent=2) + "\n")
    print(f"Wrote {target} (SHA-256 {digest}) after {len(seen)} archive member(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
