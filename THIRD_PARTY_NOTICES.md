# Third-party notices

Splash 'n' Splat is licensed under the MIT License; see [LICENSE](LICENSE).
This covers the code, the shaders, the scenes, the sounds (synthesized in code) and all the polar bears, snowdrifts and landscapes, which the game draws in code.

The game includes, or is built with, the following third-party components.
Each keeps its own license.
The release packages carry all the license texts in the directory `licenses/`.

## Distributed with the game

### Godot Engine

* Version: 4.6.2 (.NET)
* License: MIT
* Copyright (c) 2014-present Godot Engine contributors; Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur
* Source: https://godotengine.org
* License text: [licenses/godot/LICENSE.txt](licenses/godot/LICENSE.txt)

Godot Engine itself includes third-party components under their own licenses, e.g., FreeType, the fonts and the image libraries.
Their notices are in [licenses/godot/COPYRIGHT.txt](licenses/godot/COPYRIGHT.txt), generated from the Godot binary with `dev/write_godot_licenses.gd`.

### .NET runtime

* License: MIT
* Copyright (c) .NET Foundation and Contributors
* Source: https://github.com/dotnet/runtime
* Third-party notices: https://github.com/dotnet/runtime/blob/main/THIRD-PARTY-NOTICES.TXT

The .NET build of Godot bundles the .NET runtime with the exported game.

### ONNX Runtime

* Package: `Microsoft.ML.OnnxRuntime` 1.24.4
* License: MIT
* Copyright (c) Microsoft Corporation
* Source: https://github.com/microsoft/onnxruntime
* License text and third-party notices: included in the release packages as `licenses/onnxruntime/LICENSE` and `licenses/onnxruntime/ThirdPartyNotices.txt`

### YOLOX-Body-Head-Hand (hand detection)

* File: `scenes/hand_tracker/yolox/model/yolox_n_body_head_hand_Nx3xHxW.onnx`
* License: Apache License 2.0
* Copyright (c) PINTO0309 (Katsuya Hyodo); based on YOLOX by Megvii (https://github.com/Megvii-BaseDetection/YOLOX)
* Source: https://github.com/PINTO0309/PINTO_model_zoo/tree/main/426_YOLOX-Body-Head-Hand, downloaded from the archive in its `download_n.sh` (SHA-256 recorded in `dev/computer_vision/models_manifest.json`)
* License text: [scenes/hand_tracker/yolox/model/LICENSE](scenes/hand_tracker/yolox/model/LICENSE)

We distribute the model unmodified.

### Silicon Labs MLTK rock_paper_scissors (gesture classification)

* File: `scenes/hand_tracker/gesture/model/rock_paper_scissors_float32.onnx`
* License: Zlib
* Copyright (c) Silicon Laboratories Inc.
* Source: https://github.com/SiliconLabs/mltk/blob/master/mltk/models/siliconlabs/rock_paper_scissors.py, pre-trained archive `rock_paper_scissors.mltk.zip`
* License text: [scenes/hand_tracker/gesture/model/LICENSE.md](scenes/hand_tracker/gesture/model/LICENSE.md)

**Altered:** we converted the original Keras model (`rock_paper_scissors.h5`) to ONNX with tf2onnx (`dev/computer_vision/download_and_convert_models.py`); the weights are unchanged.

### Our fist classifier

* File: `scenes/hand_tracker/gesture/model/fist_classifier.onnx`
* License: MIT (ours), like the game
* Trained by `dev/computer_vision/train_fist_classifier.py` on our own recordings, starting from the ImageNet weights of MobileNetV3-Small from Keras Applications (Apache License 2.0, https://github.com/keras-team/keras-applications; the weights were published by the Keras team under the same license)

### Natural Earth (the coastlines of the travel map)

* File: `scenes/travel_map/arctic_map.json`
* License: public domain (https://www.naturalearthdata.com/about/terms-of-use/)
* Source: the 1:50m land polygons and land borders, version 5.1.2, https://github.com/nvkelso/natural-earth-vector
* Made with Natural Earth. Free vector and raster map data @ naturalearthdata.com.

**Altered:** `dev/maps/make_travel_map.py` projects the polygons (azimuthal equidistant), clips them to the screen and simplifies them.

## Used only for development, not distributed

| Component | Version | License | Source |
|---|---|---|---|
| xUnit.net (`xunit`, `xunit.runner.visualstudio`) | 2.9.3, 4.0.1 | Apache-2.0 | https://xunit.net |
| Microsoft.NET.Test.Sdk | 18.11.0 | MIT | https://github.com/microsoft/vstest |
| StbImageSharp | 2.30.16 | Unlicense or MIT | https://github.com/StbSharp/StbImageSharp |
| gdtoolkit (`gdformat`, `gdlint`) | 4.5.0 | MIT | https://github.com/Scony/godot-gdscript-toolkit |
| black | 24.10.0 | MIT | https://github.com/psf/black |
| TensorFlow (CPU), tf2onnx, ONNX, ONNX Runtime, NumPy, Pillow, py7zr | see `dev/computer_vision/requirements.txt` | Apache-2.0 / MIT / BSD / HPND / LGPL-2.1 | PyPI |
| YOLOX-Body-Head-Hand medium (labeling the training recordings) | epoch 299 | Apache-2.0 | PINTO model zoo 426, `download_m.sh` |
| Rock/paper/scissors dataset v2 (validating the conversion) | v2 | Zlib | https://github.com/SiliconLabs/mltk_assets |

The test images in `tests/SplashNSplat.Tests/data/`:

* `astronaut_640x480.png` and `crew_of_six_640x480.png` are public-domain NASA photos: the scikit-image "astronaut" (Eileen Collins) and "Expedition 38 crew members pose for an in-flight crew portrait" (ISS038-E-054970).
* `rps/*.png` are images of the Silicon Labs rock/paper/scissors dataset v2 (Zlib).
