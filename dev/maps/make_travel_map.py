#!/usr/bin/env python3

"""
Make the vector map of the travel map from the real coastlines of the world.

We download the land polygons of Natural Earth (1:50m, public domain, see
https://www.naturalearthdata.com/about/terms-of-use/), pinned by their SHA-256,
project them with an azimuthal equidistant projection centered on the North
Atlantic (so that Zurich, Greenland, Astana and the North Pole all fit, with the North
Pole on the top), clip them to the screen of 1920x1080, simplify them to about
a pixel, and write them to scenes/travel_map/arctic_map.json with the circles
of latitude, the meridians and the places of the game.

    venv/bin/python dev/maps/make_travel_map.py
"""

import argparse
import hashlib
import json
import math
import pathlib
import sys
import urllib.request
from typing import Dict, List, Sequence, Tuple

import numpy as np

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
BASE_URL = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/"

#: The downloads by file name, pinned by their SHA-256: the land and the land borders.
DOWNLOADS = {
    "ne_50m_land.geojson": "e874b27a51d146452be360cafb3cc50c86001074a67d534113e6534682f9826b",
    "ne_50m_admin_0_boundary_lines_land.geojson": (
        "2faac4f6b34386f3d21b6e018cf151f241f00e5c936d44dd17d7d9bfb147fa48"
    ),
}
URL = BASE_URL + "ne_50m_land.geojson"
OUTPUT = REPO_ROOT / "scenes" / "travel_map" / "arctic_map.json"

WIDTH, HEIGHT = 1920.0, 1080.0

# NOTE (mristin):
# The places as (latitude, longitude): Ilulissat with its ice fjord for Greenland,
# Tromsø for Norway, Rovaniemi for Finland and the capitals for the others.
PLACES = {
    "Zurich": (47.3769, 8.5417),
    "The North Pole": (90.0, 0.0),
    "Greenland": (69.2198, -51.0986),
    "Iceland": (64.1466, -21.9426),
    "Norway": (69.6492, 18.9553),
    "Sweden": (59.3293, 18.0686),
    "Finland": (66.5039, 25.7294),
    "Estonia": (59.4370, 24.7536),
    "Latvia": (56.9496, 24.1052),
    "Lithuania": (54.6872, 25.2797),
    "Belarus": (53.9045, 27.5615),
    "Ukraine": (50.4501, 30.5234),
    "Russia": (55.7558, 37.6173),
    "Kazakhstan": (51.1694, 71.4491),
}

CENTER = (66.0, 12.0)

# The free room around the places, as fractions of the screen.
MARGIN_X = 0.08
MARGIN_TOP = 0.12
MARGIN_BOTTOM = 0.16

Point = Tuple[float, float]


def project(lat: np.ndarray, lon: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    """Project with the azimuthal equidistant projection around CENTER (in radians of arc)."""
    phi0, lam0 = math.radians(CENTER[0]), math.radians(CENTER[1])
    phi, lam = np.radians(lat), np.radians(lon)
    cos_c = np.sin(phi0) * np.sin(phi) + np.cos(phi0) * np.cos(phi) * np.cos(lam - lam0)
    c = np.arccos(np.clip(cos_c, -1.0, 1.0))
    k = np.where(c > 1e-9, c / np.maximum(np.sin(c), 1e-9), 1.0)
    x = k * np.cos(phi) * np.sin(lam - lam0)
    y = k * (np.cos(phi0) * np.sin(phi) - np.sin(phi0) * np.cos(phi) * np.cos(lam - lam0))
    return x, y


def fit_to_screen() -> Tuple[float, float, float]:
    """Find the scale and the offset which fit the places into the screen with margins."""
    lat = np.array([p[0] for p in PLACES.values()])
    lon = np.array([p[1] for p in PLACES.values()])
    x, y = project(lat, lon)
    usable_w = WIDTH * (1 - 2 * MARGIN_X)
    usable_h = HEIGHT * (1 - MARGIN_TOP - MARGIN_BOTTOM)
    scale = min(usable_w / (x.max() - x.min()), usable_h / (y.max() - y.min()))
    offset_x = WIDTH / 2 - scale * (x.max() + x.min()) / 2
    # NOTE (mristin):
    # The screen y grows downwards; the top of the places goes below the top margin.
    offset_y = HEIGHT * MARGIN_TOP + scale * y.max()
    used_h = scale * (y.max() - y.min())
    offset_y += (usable_h - used_h) / 2
    return scale, offset_x, offset_y


def to_screen(lat: np.ndarray, lon: np.ndarray, fit: Tuple[float, float, float]) -> np.ndarray:
    scale, offset_x, offset_y = fit
    x, y = project(lat, lon)
    return np.stack([offset_x + scale * x, offset_y - scale * y], axis=1)


def clip_polygon(points: List[Point], box: Tuple[float, float, float, float]) -> List[Point]:
    """Clip a closed polygon to the box (Sutherland-Hodgman)."""
    x_min, y_min, x_max, y_max = box
    edges = [
        (lambda p: p[0] >= x_min, lambda a, b: _cut_x(a, b, x_min)),
        (lambda p: p[0] <= x_max, lambda a, b: _cut_x(a, b, x_max)),
        (lambda p: p[1] >= y_min, lambda a, b: _cut_y(a, b, y_min)),
        (lambda p: p[1] <= y_max, lambda a, b: _cut_y(a, b, y_max)),
    ]
    for inside, cut in edges:
        if not points:
            return []
        result = []
        for i, current in enumerate(points):
            previous = points[i - 1]
            if inside(current):
                if not inside(previous):
                    result.append(cut(previous, current))
                result.append(current)
            elif inside(previous):
                result.append(cut(previous, current))
        points = result
    return points


def _cut_x(a: Point, b: Point, x: float) -> Point:
    t = (x - a[0]) / (b[0] - a[0])
    return (x, a[1] + t * (b[1] - a[1]))


def _cut_y(a: Point, b: Point, y: float) -> Point:
    t = (y - a[1]) / (b[1] - a[1])
    return (a[0] + t * (b[0] - a[0]), y)


def simplify(points: Sequence[Point], tolerance: float) -> List[Point]:
    """Simplify an open polyline (Douglas-Peucker)."""
    if len(points) < 3:
        return list(points)
    a, b = np.array(points[0]), np.array(points[-1])
    middle = np.array(points[1:-1])
    ab = b - a
    length = float(np.hypot(*ab))
    if length < 1e-9:
        distances = np.hypot(*(middle - a).T)
    else:
        distances = np.abs(ab[0] * (middle[:, 1] - a[1]) - ab[1] * (middle[:, 0] - a[0])) / length
    index = int(np.argmax(distances))
    if distances[index] <= tolerance:
        return [points[0], points[-1]]
    split = index + 1
    left = simplify(points[: split + 1], tolerance)
    right = simplify(points[split:], tolerance)
    return left[:-1] + right


def simplify_ring(points: List[Point], tolerance: float) -> List[Point]:
    """Simplify a closed ring, split at its two farthest-apart points."""
    if len(points) < 8:
        return points
    array = np.array(points)
    first = 0
    second = int(np.argmax(np.hypot(*(array - array[first]).T)))
    a = simplify(points[first : second + 1], tolerance)
    b = simplify(points[second:] + points[: first + 1], tolerance)
    return a[:-1] + b[:-1]


def area(points: Sequence[Point]) -> float:
    array = np.array(points)
    x, y = array[:, 0], array[:, 1]
    return 0.5 * abs(float(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1))))


def rings_of(feature: Dict) -> List[List[List[float]]]:
    """Return the outer rings of a Polygon or MultiPolygon (the land has no holes we need)."""
    geometry = feature["geometry"]
    if geometry["type"] == "Polygon":
        return [geometry["coordinates"][0]]
    return [polygon[0] for polygon in geometry["coordinates"]]


def polyline_segments(
    screen: np.ndarray, box: Tuple[float, float, float, float]
) -> List[List[Point]]:
    """Split a projected polyline into the runs of points inside the box."""
    x_min, y_min, x_max, y_max = box
    runs: List[List[Point]] = []
    run: List[Point] = []
    for x, y in screen:
        if x_min <= x <= x_max and y_min <= y <= y_max:
            run.append((float(x), float(y)))
        else:
            if len(run) > 1:
                runs.append(run)
            run = []
    if len(run) > 1:
        runs.append(run)
    return runs


def flat(points: Sequence[Point]) -> List[float]:
    return [round(v, 1) for point in points for v in point]


def download(cache_dir: pathlib.Path, name: str) -> bytes:
    """Download a file of Natural Earth once into the cache, and check its SHA-256."""
    cache = cache_dir / name
    if not cache.exists():
        cache_dir.mkdir(parents=True, exist_ok=True)
        print(f"Downloading {BASE_URL + name} ...", flush=True)
        request = urllib.request.Request(
            BASE_URL + name, headers={"User-Agent": "splash-n-splat-map-setup"}
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            cache.write_bytes(response.read())
    data = cache.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != DOWNLOADS[name]:
        raise RuntimeError(f"Unexpected SHA-256 of {cache}: {digest}, expected {DOWNLOADS[name]}")
    return data


def lines_of(feature: Dict) -> List[List[List[float]]]:
    """Return the lines of a LineString or a MultiLineString."""
    geometry = feature["geometry"]
    if geometry["type"] == "LineString":
        return [geometry["coordinates"]]
    return list(geometry["coordinates"])


def main() -> int:
    """Execute the entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", default=str(REPO_ROOT / ".cache" / "natural_earth"))
    parser.add_argument(
        "--tolerance",
        type=float,
        default=0.25,
        help="Simplification in pixels; fine, since the travel map zooms in up to tenfold",
    )
    args = parser.parse_args()

    cache_dir = pathlib.Path(args.cache_dir)
    land = json.loads(download(cache_dir, "ne_50m_land.geojson"))
    boundaries = json.loads(download(cache_dir, "ne_50m_admin_0_boundary_lines_land.geojson"))
    fit = fit_to_screen()
    box = (-20.0, -20.0, WIDTH + 20, HEIGHT + 20)

    polygons = []
    for feature in land["features"]:
        for ring in rings_of(feature):
            coordinates = np.array(ring)
            screen = to_screen(coordinates[:, 1], coordinates[:, 0], fit)
            # NOTE (mristin):
            # Far from the center, the projection stretches the land a lot; we only
            # keep the land which comes near the screen.
            near = (
                (screen[:, 0] > -WIDTH)
                & (screen[:, 0] < 2 * WIDTH)
                & (screen[:, 1] > -HEIGHT)
                & (screen[:, 1] < 2 * HEIGHT)
            )
            if not near.all():
                if not near.any():
                    continue
            points = [(float(x), float(y)) for x, y in screen[:-1]]
            clipped = clip_polygon(points, box)
            if len(clipped) < 3:
                continue
            simplified = simplify_ring(clipped, args.tolerance)
            if len(simplified) >= 3 and area(simplified) >= 40.0:
                polygons.append(flat(simplified))

    # NOTE (mristin):
    # The borders between the countries, so that a zoomed-in map still shows
    # where the plane flies.
    borders = []
    for feature in boundaries["features"]:
        for line in lines_of(feature):
            coordinates = np.array(line)
            screen = to_screen(coordinates[:, 1], coordinates[:, 0], fit)
            for run in polyline_segments(screen, box):
                simplified = simplify(run, args.tolerance)
                if len(simplified) >= 2:
                    borders.append(flat(simplified))

    graticule = []
    for lat in (50, 60, 70, 80):
        lon = np.linspace(-180, 180, 721)
        screen = to_screen(np.full_like(lon, lat), lon, fit)
        graticule += [flat(simplify(run, 0.5)) for run in polyline_segments(screen, box)]
    for lon in range(-180, 180, 20):
        lat = np.linspace(40, 90, 201)
        screen = to_screen(lat, np.full_like(lat, lon), fit)
        graticule += [flat(simplify(run, 0.5)) for run in polyline_segments(screen, box)]

    places = {}
    for name, (lat, lon) in PLACES.items():
        point = to_screen(np.array([lat]), np.array([lon]), fit)[0]
        places[name] = [round(float(point[0]), 1), round(float(point[1]), 1)]

    result = {
        "_comment": (
            "Generated by dev/maps/make_travel_map.py from the land polygons and the land "
            "borders of Natural Earth (1:50m, public domain), in screen pixels of 1920x1080."
        ),
        "source": URL,
        "projection": f"azimuthal equidistant, centered at {CENTER[0]} N, {CENTER[1]} E",
        "land": polygons,
        "graticule": graticule,
        "borders": borders,
        "places": places,
    }
    OUTPUT.write_text(json.dumps(result, separators=(",", ":")) + "\n")
    points = sum(len(p) // 2 for p in polygons)
    print(
        f"Wrote {OUTPUT} ({OUTPUT.stat().st_size // 1024} KB): {len(polygons)} land polygons "
        f"with {points} points; places: {places}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
