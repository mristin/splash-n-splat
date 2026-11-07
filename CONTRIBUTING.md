# Contributing

Thank you for helping with Splash 'n' Splat!
This guide explains how the game is built, how to set up the development environment, how to get the models, and how to run, test, benchmark and debug the game.

## Overview

The game is made with [Godot] 4.6 (.NET), in GDScript and C#:

* **The hand vision is in C#** (`scenes/hand_tracker/`), since it is performance-critical and uses [ONNX Runtime].
  The core (`scenes/hand_tracker/core/`) and the model wrappers do not depend on Godot, so we unit-test them with plain .NET in `tests/SplashNSplat.Tests/`.
  * `YoloxHandDetector` letterboxes the frame, runs YOLOX and decodes all the hands with our own non-maximum suppression.
  * `MultiHandTracker` follows any number of hands with an alpha-beta filter, a greedy assignment by IoU and center distance, and a re-acquisition of fast hands; tracks survive brief misses and expire after `MaxAgeSeconds`.
    A new track starts only from a confident detection (0.6) and becomes a hand only after three detections with a smoothed score of 0.55, since nano fires weakly on elbows, forearms and colorful furniture (see `dev/computer_vision/evaluate_detector.py`, which compares nano with the large YOLOX on the recordings and draws its false positives).
  * `FistClassifier` (ours) or `GestureClassifier` (MLTK) classify the square crops of the hands.
  * `GestureStateMachine` smooths the probabilities per hand (EMA), confirms the gestures with hysteresis and fires exactly once per OPEN to FIST transition, with a cooldown; only a confirmed OPEN of the same hand re-arms it.
    Every hand of every player aims and throws on its own; a hand which first appears as a fist does not throw until it opens.
  * `VisionPipeline` runs it all at the cadence of the current workload level; `AdaptiveScheduler` lowers the detector resolution, its rate and the number of classified hands when the latencies or the render rate get bad.
  * `HandVisionService` (a Godot node) captures the webcam, runs the pipeline on a background thread, and offers the game a plain API: `GetAims()` (the smoothed aim of every hand, mapped to the screen), `GetCameraTexture()` and `GetAimRegion()` for the dimmed camera overlay, and the `ShotFired` signal.
* **The game is in GDScript** (`scenes/`): `game` (the game controller and the rules), `level` (the base of the worlds), `winter_level` (the North Pole with its hiding places, which also holds the covers and the themes shared by the worlds), `greenland_level` (the fjord with the walruses, the seals and the orcas), `country_level` (the eleven winter countries and Zurich, all from one scene and the data in `countries.gd`), `critter` (the base of the animals which pop up and throw, and the `Beast`, the `Bird` and the `Ladybird` which draw most of them from their looks), `polar_bear`, `rover` (what crosses the screen on its own: the penguins and the snowy owls which throw while they move, the kittens which must not be hit, the balloons with the boosters, and `Rovers` which sends them and keeps the boosters), `snowball`, `splat`, `snow_overlay`, `camera_overlay` (the players see themselves dimly, mirrored, over the game, exactly aligned with their aims), `hud`, `travel_map` (the flights between the worlds), `aim` (an outline of a snowball per hand, no weapon sights), `sound` and `debug_overlay`.
* The development tools live in `dev/`, the model tools in `dev/computer_vision/`.

This is a game for children, so we avoid violence as well as sad and realistic themes: nothing gets hurt, a hit animal only gets dizzy.

[Godot]: https://godotengine.org
[ONNX Runtime]: https://onnxruntime.ai

### The gameplay

The critters (the polar bears, and in Greenland the walruses and the seals) pop up at the hiding places (`CoverSpot` nodes in the level scenes, e.g., `scenes/winter_level/winter_level.tscn`; move them in the editor).
Mostly one critter is out at a time, seldom two (`LevelRules.second_bear_chance`), never three.
The difficulty adapts from world to world (`LevelRules.challenge`, 0 to 2): a too easy win (no snowball taken, or at most one critter in ten could throw) raises it, and then often two critters come out at once, at the top sometimes three; a lost world lowers it again. At most two snowballs fly at once at every challenge.
A critter stays out for `LevelRules.exposure_seconds()` (5.1 s at the start, 3.0 s at the end), winds up for 0.7 s with a "!" bubble whose ring closes, and throws.
The snowball flies toward the player for 1.3 to 1.9 s, growing, with a landing ring.

The hand tracking is not pixel-precise, so the bears are big (two rows of hiding places, the near bears more than a third of the screen high), barely move, and have a generous hit area (45 px of tolerance).
The player is never helpless (our fairness mechanism):

1. hit the bear before it throws (the quicker, the more points),
2. or intercept its snowball in the air (the hit area of a snowball is generous),
3. and at most two snowballs fly at once; a bear which would exceed that ducks away without throwing.

A snowball which gets through adds frost and a lump of snow along the edges of the screen (`SnowAccumulation`), at most 27% per edge, so at least 46% of the width and the height always stay clear.

The critters throw at the heads of the players.
The detector finds the heads in the same run as the hands (`YoloxHandDetector.Heads`, at a score of 0.5; decoding them costs nearly nothing), `HandVisionService.GetHeads()` maps them to the screen like the aims and eases them between the detections, and `HeadOutlines` draws a soft, glowing ellipse around every head (a shader, `scenes/aim/head_outline.gdshader`, with a faint shadow so that it shows on the snow, too), orange and pulsing while a snowball flies at it.
A critter throws at a random head; when the snowball lands, it hits only if a head is still there (within its outline plus 30 px, all enlarged by 15%, so that the players have to really duck), otherwise the player dodged it (10 points).
Without heads in the picture (or without a camera, as in the tests), the snowballs land at a random spot and always hit, as before.

The players have the energy for ten snowballs (the bar at the top right).
A won level shows the level-finished screen with up to three stars (by the energy left) and leads to the next world; after the last one, the game-finished screen celebrates the whole trip (the worlds, the critters, the snowballs knocked out and the score of all the won worlds, with confetti), and a fist after 15 s starts over (the fists before do not skip the celebration).
Start at another world with `-- --level=2`.

Before every new world, a little plane flies there on an old map (`scenes/travel_map/`): from Zurich to the North Pole when the game starts, then on to Greenland, and back to the North Pole after the last world; the fists do not skip the flight, since the players keep throwing from the world before.
The map shows the real coastlines and the borders between the countries of [Natural Earth] (public domain).
Every flight takes the same time, and the map zooms in (up to tenfold) so that every route is about the same length on the screen: a short hop like Minsk to Kyiv is as long to watch as Astana to Zurich.
`dev/maps/make_travel_map.py` downloads them (pinned by their SHA-256), projects them around the North Atlantic, clips and simplifies them, and writes `scenes/travel_map/arctic_map.json` with the circles of latitude, the meridians and the places; run it again when you add a place:

```
venv/bin/python dev/maps/make_travel_map.py
```

[Natural Earth]: https://www.naturalearthdata.com

In Greenland, a big orca leaps slowly (6.5 s) out of the sea every 8 to 14 s, in one of the lanes of `GreenlandLevel.orca_lanes`; it never throws, and a hit is a bonus of 150 points which does not count towards the 20 critters.
Below its water line, the orca paints the sea over itself in the exact gradient of the backdrop, like the covers paint the ground below a hidden critter.

In every world, rovers cross the screen now and then (`scenes/rover/`, sent by `Rovers`), at most one walker (along `Level.walk_y`, in front of everything), one owl and one balloon at a time:

* a penguin walks (10 s) or a snowy owl flies (8.5 s) across every 9 to 14 s and throws at most twice while it keeps moving, every time after the same 0.7 s "!" wind-up as the critters, and only while at most two snowballs fly; a hit is a bonus of 150 points which does not count towards the 20 critters;
* a kitten strolls by every 12 to 20 s: a hit kitten sits and cries (with a sad meow), costs the energy of one snowball, and then runs off;
* a balloon brings a booster every 14 to 22 s: rapid fire (a held fist throws every 0.22 s) and big snowballs (they reach 60 px farther, and the aim outlines grow while they last; the icon shows a small snowball grown big, and collecting it says "Easier to hit!", since the players did not understand the plain white disc of before) last 15 s (`LevelRules.boost_seconds`, shown with a running-out ring under the energy bar), and health takes back three snowballs at once (it only comes when the players have taken some).

To make another world (e.g., the summer world with water balloons), add a script which extends `Level` (its texts, its theme and its critters), a `LevelTheme` with a `ProjectileStyle`, a level scene with its own backdrop and hiding places, and add the scene to `Game._LEVEL_SCENES`.
New critters extend `Critter` and only draw themselves; keep their size, so that every cover hides them.

The countries after Greenland are data: add one to `Countries.all()` in `scenes/country_level/countries.gd` with its animals (a `Beast` or a `Bird` with its look: colors, ears, snout, beak and features like a mane, antlers or stripes), its six covers, its colors, its terrain and its landmark (drawn in `landmarks.gd`), add its place to `dev/maps/make_travel_map.py` and run it.
`tests/godot/test_levels.gd` plays every level: every kind of critter comes out, gets hit and throws, and every level is on the travel map.

### The hand tracking in short

* The hands are detected with [YOLOX-Body-Head-Hand] (nano, Apache-2.0) and tracked with an alpha-beta filter, so that every hand keeps its id; any number of hands can be in the picture.
* Each tracked hand is cropped and classified as fist or not, directly from the image (no hand landmarks).
  A hand throws exactly once when it closes from open to a fist, and has to open again before the next throw.
* Every hand aims and throws on its own.
* The players see themselves dimly over the game, mirrored, with a snowball outline where each hand aims.
* Everything runs with ONNX Runtime on the CPU, on a background thread, and adapts the workload to the speed of the computer.

[YOLOX-Body-Head-Hand]: https://github.com/PINTO0309/PINTO_model_zoo/tree/main/426_YOLOX-Body-Head-Hand

The structure of the game and the inference loop were adapted from [head-invaders].

[head-invaders]: https://github.com/mristin/head-invaders

## Quick start

You need a webcam with 640x480, the .NET build of Godot 4.6.2, the .NET 8 SDK and Python 3.10+ (see below for the details).

```
python3 -m venv venv && touch venv/.gdignore
venv/bin/pip install -r dev/requirements.txt -r dev/computer_vision/requirements.txt
venv/bin/python dev/computer_vision/download_and_convert_models.py
dotnet build SplashNSplat.sln
$GODOT --path .
```

Start with `$GODOT --path . -- --debug` for the debug overlay (camera and render rates, inference latencies, hands, gesture probabilities); press Escape twice to quit.

## Setting up the development environment

You need:

* [Git] and [Git LFS], since we keep the ONNX models and the images in LFS,
* the [.NET 8 SDK],
* the **.NET** build of [Godot 4.6.2] (also called "mono"), and
* [Python] 3.10 or newer, for the model tools, the formatters and the linters.

[Git]: https://git-scm.com
[Git LFS]: https://git-lfs.com
[.NET 8 SDK]: https://dotnet.microsoft.com/download/dotnet/8.0
[Godot 4.6.2]: https://godotengine.org/download/archive/4.6.2-stable/
[Python]: https://www.python.org/downloads/

Our scripts find Godot through the `GODOT` environment variable, e.g.:

```
export GODOT=~/apps/Godot_v4.6.2-stable_mono_linux_x86_64/Godot_v4.6.2-stable_mono_linux.x86_64
```

Set up the Python environment (do not skip the `.gdignore`, or Godot scans the whole virtual environment):

```
python3 -m venv venv
touch venv/.gdignore
venv/bin/pip install -r dev/requirements.txt -r dev/computer_vision/requirements.txt
```

`dev/requirements.txt` holds the formatters and linters; `dev/computer_vision/requirements.txt` pins the model tools (TensorFlow 2.15, tf2onnx 1.16.1, ONNX 1.16.2, ONNX Runtime 1.19.2, NumPy 1.26), which must match each other.

## The models

Downloading the models is a setup step; the game never downloads anything.

```
venv/bin/python dev/computer_vision/download_and_convert_models.py
```

The script:

1. downloads the YOLOX-Body-Head-Hand nano archive (252 MB, from the URL in the model zoo's `download_n.sh`), the MLTK `rock_paper_scissors.mltk.zip`, the MLTK rock/paper/scissors dataset and the licenses, all pinned by their SHA-256, into `.cache/models/` (downloaded only once),
2. extracts the YOLOX model with the dynamic input shape (so that the game can change the resolution at runtime), checks it, compares it with the fixed 320x256 variant and benchmarks it,
3. extracts the MLTK archive, checks the label order (`rock, paper, scissor, _unknown_`), converts the original Keras model to a float32 ONNX model with tf2onnx, and the int8 TFLite model to ONNX for comparison,
4. checks the models with `onnx.checker`, runs them with the CPU execution provider, and compares Keras, TFLite (float32 and int8) and ONNX on synthetic inputs and 400 dataset images,
5. writes the metadata (input shape, layout, dtype, channel order, normalization, labels) next to the models, and `dev/computer_vision/models_manifest.json` (sources and hashes) and `dev/computer_vision/models_validation_report.json`.

It fails loudly if a hash, a label order or a conversion does not match.

The MLTK input is 84x84x1 (not 96x96, as its description says): the luma (PIL "L"), resized bilinearly and standardized per sample, `(x - mean) / (std + 1e-6)`.
The float32 ONNX model reproduces Keras (max. abs. error 4.8e-7, 100% class agreement, 96.8% accuracy on 400 dataset images), and is faster than the int8 one (0.21 vs. 0.72 ms), so we use float32.

### Our own fist classifier

The MLTK model was trained on photos of hands lying on a table, and recognizes fists poorly on webcam images (see the measurements below).
The game therefore prefers our own fist classifier, `scenes/hand_tracker/gesture/model/fist_classifier.onnx`, if it exists: an ImageNet-pretrained MobileNetV3-Small (96x96 RGB) fine-tuned on recordings of players.

1. Record (about 4 minutes per session; follow the prompts on the screen; vary the place, the light and the people):

   ```
   $GODOT --path . scenes/tests/gesture_recorder/gesture_recorder.tscn
   ```

   Add `-- --program=face` for a session of fists and open hands in front of the face and the chest, which are the hardest to recognize, and `--out=DIR` to record elsewhere.
   The frames go to `~/.local/share/godot/app_userdata/Splash 'n' Splat/recordings/<session>/`, outside of the repository, since they show the players.
   Do not commit them.

2. Download the large YOLOX (medium) which finds the hands in the recordings more reliably than the game's nano (it streams a 7 GB archive and keeps only the 100 MB model):

   ```
   venv/bin/python dev/computer_vision/download_labeling_detector.py
   ```

3. Train, evaluate against MLTK, convert to ONNX and install:

   ```
   venv/bin/python dev/computer_vision/train_fist_classifier.py \
       --sessions ~/.local/share/godot/app_userdata/"Splash 'n' Splat"/recordings/*
   ```

   Or keep all the recordings in one dataset directory with `sessions/`, `gameplay/` and a `split.json` which lists the test sessions (all the others are for training), and train with:

   ```
   venv/bin/python dev/computer_vision/train_fist_classifier.py --dataset ~/splash-n-splat-dataset
   ```

   With `--sessions`, by default, we test on a random 25% of 2-second chunks of the frames (`--split chunks`); `--split random` splits by single frames (optimistic, since neighboring frames are nearly identical), and `--split holdout --holdout <session>` tests on whole sessions (the most honest).
   The augmentation shifts, scales and rotates the crop window, flips it, and varies the brightness, the contrast, the color and the gamma, and adds a backlight from a random side (a dark hand in front of a bright window).
   The first layer of the model stretches every crop to the brightness and the contrast of its center, where the hand is, so that a dark hand in front of a window looks like a hand in a well-lit room; it is part of the ONNX model, so the game does exactly the same.
   A training takes about 40 minutes on the laptop and survives a restart: every run keeps its configuration, its state and a checkpoint of the model and of the optimizer after every epoch in its own directory `<time>/` in the directory of the trainings (`--trainings-dir`, by default `~/splash-n-splat-trainings`); continue the last unfinished run, after the epoch it saved last, with:

   ```
   venv/bin/python dev/computer_vision/train_fist_classifier.py --dataset ~/splash-n-splat-dataset \
       --trainings-dir ~/splash-n-splat-trainings --resume
   ```

   A run resumes only with the same data and arguments; otherwise, start a new one.
   The fine-tuning overfits after a few epochs (on the held-out hands, the accuracy peaked at the third of 15 epochs and then sank by two points), so the training keeps the model of the epoch with the lowest held-out loss (`finetune-best/` of the run) and installs it instead of the last one; the report gives its epoch.
   Since the held-out hands are also the test hands, this choice makes the reported numbers slightly optimistic.
   The augmented crops (about 3 GB for 100 000 of them) go to a memory-mapped file in `crops/` of the directory of the trainings, and every batch is read from there, so the training needs about as much memory for a large dataset as for a small one (holding them in memory, and copying them into TensorFlow and its shuffle buffer, froze the laptop).
   The report goes to `dev/computer_vision/fist_classifier_report.json` (and to the directory of the run); it names the recordings and so the people in them, so it is not versioned and stays local. `--dry-run` trains without installing.

The installed classifier was trained on about 21600 frames of 14 recordings (about 35900 hands as found by YOLOX-m): sessions of four people, two adults and two children, in different places, lighting and clothes, in front of a bright window and kneeling (the hands seen from below, at the height of a child), and four gameplay recordings with automatic labels, three of them reviewed by eye.
We installed the third of five epochs of the fine-tuning, the one with the lowest loss on the test sessions (see above).
It was tested on eight whole sessions which it never saw (`split.json` of the dataset): one of each person, one in other clothes and another room, one with the hands in front of the face, one in front of a bright window, and one kneeling; the children's sessions with their corrected labels (see above).
Per single crop at the threshold 0.5 (the game additionally smooths over frames and confirms a fist twice), without the first second of every phase (see below), compared with the previous classifier, which had not seen the gameplay of the second child nor the kneeling:

| Test session | ROC AUC | fists recognized | open hands taken for fists | accuracy |
|---|---|---|---|---|
| first adult, full program | 0.989 (0.982) | 96% (95%) | 4.8% (4.9%) | 96% (95%) |
| first adult, other clothes and room | 0.982 (0.990) | 90% (95%) | 3.7% (3.3%) | 94% (96%) |
| first adult, hands in front of the face | 0.999 (1.000) | 99% (100%) | 0.4% (2.4%) | 99% (99%) |
| first adult, in front of a bright window | 0.997 (0.991) | 99% (100%) | 1.9% (3.2%) | 98% (98%) |
| first adult, kneeling | 0.988 (0.962) | 95% (93%) | 7.4% (15.8%) | 94% (88%) |
| second adult (thumb on top of the fist) | 0.976 (0.959) | 87% (85%) | 4.8% (6.3%) | 91% (89%) |
| first child | 0.990 (0.995) | 94% (95%) | 1.5% (2.1%) | 97% (97%) |
| second child | 0.974 (0.982) | 92% (94%) | 2.2% (5.1%) | 95% (95%) |
| all eight | **0.986** (0.981) | 94% (94%) | **3.7%** (6.1%) | **95%** (94%) |

The new classifier takes far fewer open hands for fists, which are the false throws, especially kneeling and with the children.
Most of what is left are not mistakes of the classifier, but of the labels, as we saw on contact sheets of the failures:

* the first second of a phase often still shows the pose of the phase before; the training and the evaluation therefore skip it (`--settle-seconds`, 1 by default; without skipping it, the accuracy on all eight is 94.4%),
* the labeling detector finds "hands" in plants, knees, chairs, sleeves and blankets, which get the label of the frame; its score hardly tells them apart from the real hands (on contact sheets of the test hands, about a fifth of the "hands" scored 0.4 to 0.5 were none, but also about a sixth of those scored 0.6 to 0.7), so raising `--detector-threshold` (0.4 by default; the hands are cached with their scores down to 0.25) mostly drops real, blurred or partly hidden hands, and we kept it,
* the children show open hands while asked for fists, and a real thumbs-up (the thumb sticking out) while asked for fists turned sideways, which the classifier rightly calls no fist; the recorder now asks for the thumb on the fingers.

The lower recall in the other clothes and room comes from the fists moved fast, which are blurred beyond recognition; the game confirms a fist twice anyway, so a single blurred crop does not matter.
The real weakness is the second adult, who makes fists with the thumb on top, not across the fingers, held up straight: the classifier misses some of them even when they are sharp. The people differ more than the places.

The training keeps the batch normalization of MobileNetV3 in the inference mode also while fine-tuning (`base(inputs, training=False)`).
Otherwise the model normalizes with the statistics of each batch during the training, but with the lagging moving averages at inference: it then scored 99% during the training, but missed half of the fists of its own training sessions.

More players, especially children, would help the most; record them with the recorder above.

Children, especially, do not always show what the recorder asks for: they are a phase ahead, or show open hands while asked for fists.
Review their sessions with a model which was not trained on them:

```
venv/bin/python dev/computer_vision/review_labels.py --model <model> --out /tmp/review \
    ~/splash-n-splat-dataset/sessions/<session> ...
```

It splits every session into its phases (by the pauses of the countdown), prints how many hands the model agrees with per phase, and draws a contact sheet with sample crops per phase (red where the model disagrees).
Look at the flagged phases, and write the corrections to `labels.review.json` in the session (a new label per phase, or `null` to exclude it, with a note why); the training and the evaluation apply them, and the frame files stay as recorded.
In the children's sessions of 2026-11-05, the corrections raised the measured ROC AUC of a child's test session from 0.86 to 0.98: most of the "errors" were the wrong labels.

All the JSON files of the recordings, the dataset and the trained models (the frame metadata, the gameplay events, the automatic labels, the label reviews, the cached boxes, `split.json`, the manifest, the classifier metadata and the training report) are defined as pydantic models in `dev/computer_vision/dataset_schema.py`; the tools read and write them only through these models.
When you change what the C# recorders or `scenes/game/game.gd` write, update the models.
Validate a dataset and rewrite its manifest with:

```
venv/bin/python dev/computer_vision/check_dataset.py ~/splash-n-splat-dataset
```

You can also collect training data simply by playing, and label it automatically:

```
$GODOT --path . -- --record-play
venv/bin/python dev/computer_vision/auto_label_gameplay.py ~/.local/share/godot/app_userdata/"Splash 'n' Splat"/gameplay/*
```

The game records about five frames per second with the tracked hands, and logs where each hand aims, whether over a bear, and every throw (`events.jsonl`).
The labeler runs the best classifier offline, smooths it over time in both directions, and combines it with the evidence of the game: a hand which was about to throw was open, and a fast hand aims with an open hand; a hand which has just thrown or rests over a bear counts as a fist only if the classifier is clearly sure, too (p >= 0.9), since just before a throw the hand is often still closing (a claw or a blur), and a half-closed hand labeled as a fist would teach the classifier the false throws.
Whatever stays ambiguous is left out, and `labels.auto.png` shows random samples of each label for a check by eye.
Only a real fist, with the fingers closed into the palm, should throw: children, especially, curl their fingers like claws while they play, and the classifier took many of these claws for fists (in a gameplay of a child, more than half of the hands which the labeler took for fists were claws, open hands, or no hands at all).
So review the automatic fists of a gameplay recording by eye, before it goes to the training:

```
venv/bin/python dev/computer_vision/review_hands.py sheets --out /tmp/review <recording>
venv/bin/python dev/computer_vision/review_hands.py apply <recording> --label fist \
    --relabel 3,17,40-42 --exclude 5,9 --note "claws of a child"
```

The first command draws the hands labeled as fists on numbered sheets; the second writes the corrections by the numbers to `labels.reviewed.json` in the recording: the claws and the open hands become no fists, and the no hands, the blurs, the held objects and the clasped hands are excluded.
The training applies them over the automatic labels, which stay as they are.
The recorder also asks for claws ("CLAWS like a cat"), labeled as no fist.

When a fist does not throw, the players try again and again, closing the hand in about the same place; these are the hardest fists, worth reviewing and training on.
`dev/computer_vision/find_missed_fists.py` finds them: for every tracked hand, it looks for closings by the box (a fist is smaller than an open hand), not by the classifier, so it also finds the fists which the classifier missed completely; at least two closings without a throw within 4 s, while the hand stays in place, are a repeated attempt.
It draws a sheet per recording with a row per attempt: the crops over time with the closings framed in red, and the curves of the box size and of the fist probability:

```
venv/bin/python dev/computer_vision/find_missed_fists.py --out /tmp/missed \
    ~/splash-n-splat-dataset/gameplay/<recording>
```

`train_fist_classifier.py` picks up the `labels.auto.json` of a recording like any other session.
Since the labels partly come from the classifier itself, we never evaluate on them: the training puts the automatically labeled recordings always into the training set (also with `--split chunks` or `random`), and refuses them as `--holdout`.

## Performance

Measured on the target laptop (Intel i7-6600U, 2 cores / 4 threads, 15 GB RAM, Intel HD 520, no discrete GPU) with `$GODOT --path . -- --benchmark=25`, the whole game with the live vision and two hands:

| | median | worst / p95 |
|---|---|---|
| render rate | 60 fps | 54 fps (min. of the 1-second samples) |
| YOLOX nano, 320x256, 2 threads | 23.7 ms | 26.7 ms |
| fist classifier, all hands of a frame | 3.9 ms | 5.1 ms |
| copying a camera frame (main thread) | 11.2 ms | |
| vision pipeline | 16 Hz | |

The camera delivered 15 to 30 fps depending on the light (in a dark room only 7 fps, with motion blur).
Standalone, the models are faster (YOLOX 10.7 ms in Python with 2 threads, the classifier 1 ms); in the game they share the CPU with the rendering.

## Running the game

Open the project in the Godot editor and press F5, or:

```
dotnet build SplashNSplat.sln
$GODOT --path .
```

The game is played with the hands only. Press Escape twice to quit.
Options after `--`, e.g., `$GODOT --path . -- --debug --windowed`:

* `--debug`: show the debug overlay (camera, pipeline and render rates, detector and classifier latencies with median and p95, workload level, the hands with their gesture probabilities, the aims and the last shot),
* `--windowed`: a 1280x720 window instead of the full screen,
* `--no-mirror`: do not mirror the camera,
* `--camera=N`: use the N-th compatible camera,
* `--vision-config=PATH`: the vision settings (default `user://vision.json`, if it exists),
* `--benchmark=SECONDS`: play by itself, print the render rate and the latencies, and quit,
* `--no-camera`: no camera (for the automatic tests).

The vision settings are the fields of `VisionConfig` (`scenes/hand_tracker/core/VisionPipeline.cs`), e.g.:

```json
{
  "DetectorThreads": 2,
  "ClassifierHz": 20,
  "CropScale": 1.5,
  "Classifier": "auto",
  "StartLevel": 0,
  "Adaptive": true,
  "Tracker": { "MaxAgeSeconds": 0.6, "NewTrackMinScore": 0.45 },
  "Gesture": { "OpenEnter": 0.6, "FistEnter": 0.65, "ConfirmCount": 2, "CooldownSeconds": 0.25 }
}
```

The workload levels (`AdaptiveScheduler.DefaultLevels`) range from 320x256 at 15 Hz with up to 6 classified hands down to 256x192 at 10 Hz with 3 (at 160x128, nano misses about 10% of the hands, so we do not go lower); any number of hands is tracked and plays, but at most `MaxCrops` hands of the current level are classified per cycle (those which waited the longest first).

## Testing

Before you commit, run:

```
venv/bin/python dev/continuous_integration/precommit.py --overwrite
```

It formats the code (gdformat, dotnet format, black), lints the GDScripts, runs the C# unit tests, builds the game, imports the project, type-checks every GDScript and runs the Godot tests.
Without `--overwrite`, it only checks the formatting; this is what the continuous integration runs.
Select or skip steps with `--select` and `--skip`, e.g., `--select dotnet-test`.

* **C# unit tests** (`dotnet test SplashNSplat.sln`): the YOLOX pre-processing, the inverse letterbox, the decoding and the NMS, the detector on real photos, the tracker (id continuity, coasting, expiry, entering and crossing hands), the gesture state machine (no shot on an initial fist, exactly one shot per open-to-fist, re-arming, cooldown, noise), the pipeline (every hand fires on its own, no hand arms another, five players at once), the adaptive workload, and the parity of our pre-processing with the Keras model.
* **Godot tests** (`tests/godot/test_*.gd`): a headless game without a camera (title, hits, misses, interception, snow, restart, win and loss) and the bounds of the snow and the rules.
  They run with `--fixed-fps 60`: the game time advances by 1/60 s per frame, as fast as the computer can, e.g., 15 s of play in about 1.5 s:

  ```
  $GODOT --headless --fixed-fps 60 --disable-vsync --max-fps 0 --path . --script tests/godot/test_gameplay.gd
  ```

* **Camera and inference smoke test**: shows the camera with the tracked hands and their probabilities, prints the rates and the latencies every second and a summary at the end, and fails without camera frames:

  ```
  $GODOT --path . scenes/tests/vision_smoke/vision_smoke.tscn -- --seconds=30
  ```

  With `--dump=DIR`, it saves the frames which the models saw and what they found; `dev/computer_vision/inspect_dumped_frames.py DIR` compares them with the reference Python decoding and draws a contact sheet with the crops.

## Continuous integration and publishing

GitHub Actions runs the pre-commit checks on every pull request and push to `main` (`.github/workflows/ci.yaml`), and packages the game for Linux, Windows and macOS on a release (`.github/workflows/publish.yaml`), including the license texts.
When you upgrade Godot, regenerate its license texts with `$GODOT --headless --script dev/write_godot_licenses.gd`.

## Commit messages

We follow Chris Beams' [guidelines on commit messages](https://chris.beams.io/posts/git-commit/): a capitalized imperative subject of at most 50 characters without a period, a blank line, and a body wrapped at 72 characters which explains what and why.
