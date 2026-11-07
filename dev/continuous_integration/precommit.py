#!/usr/bin/env python3

"""
Run the pre-commit checks on the repository: the formatting, the linting and
the tests.

Without --overwrite, we only check the formatting. With --overwrite, we
re-format the code. In both cases, we lint the code and run all the tests
afterwards.
"""

import argparse
import concurrent.futures
import enum
import os
import pathlib
import re
import shlex
import shutil
import subprocess
import sys
import time
from typing import List, Mapping, Optional, Sequence, Tuple

REPO_ROOT = pathlib.Path(os.path.realpath(__file__)).parent.parent.parent

# NOTE (mristin):
# Godot reports some errors only on the output, but still exits with zero.
GODOT_ERROR_RE = re.compile(r"^(SCRIPT ERROR|ERROR|Parse Error)", re.MULTILINE)


class Step(enum.Enum):
    """Enumerate the pre-commit steps in the order of their execution."""

    REFORMAT = "reformat"
    LINT = "lint"
    DOTNET_TEST = "dotnet-test"
    BUILD = "build"
    IMPORT = "import"
    CHECK_SCRIPTS = "check-scripts"
    GODOT_TEST = "godot-test"


def call_and_report(
    verb: str,
    cmd: Sequence[str],
    cwd: Optional[pathlib.Path] = None,
    env: Optional[Mapping[str, str]] = None,
) -> int:
    """
    Wrap a subprocess call with the reporting to STDERR if it failed.

    Return 1 if there is an error and 0 otherwise.
    """
    cmd_str = " ".join(shlex.quote(part) for part in cmd)

    if cwd is not None:
        print(f"Executing from {cwd}: {cmd_str}", flush=True)
    else:
        print(f"Executing: {cmd_str}", flush=True)

    exit_code = subprocess.call(cmd, cwd=str(cwd) if cwd is not None else None, env=env)

    if exit_code != 0:
        print(f"Failed to {verb} with exit code {exit_code}: {cmd_str}", file=sys.stderr)
        return 1

    return 0


def find_godot(explicit: Optional[str]) -> Optional[str]:
    """Find the Godot 4.6 .NET executable in the arguments, environment or path."""
    if explicit is not None:
        return explicit

    from_env = os.environ.get("GODOT")
    if from_env:
        return from_env

    for name in ("godot", "godot4", "godot-mono", "godot4-mono"):
        found = shutil.which(name)
        if found is not None:
            return found

    return None


def run_captured(cmd: Sequence[str], timeout: float) -> Tuple[int, str, float]:
    """Run the command in the repository; return the exit code, output and duration."""
    start = time.perf_counter()
    try:
        completed = subprocess.run(
            cmd,
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
        )
        return completed.returncode, completed.stdout, time.perf_counter() - start
    except subprocess.TimeoutExpired as exception:
        output = exception.stdout or ""
        if isinstance(output, bytes):
            output = output.decode("utf-8", errors="replace")
        return (
            -1,
            output + f"\nTimed out after {timeout} seconds.",
            time.perf_counter() - start,
        )


def reformat(overwrite: bool) -> int:
    """Re-format, or only check the formatting of, the GDScript, C# and Python code."""
    print("Re-formatting..." if overwrite else "Checking the formatting...")

    # NOTE (mristin):
    # gdformat reads its configuration from gdformatrc in the repository root.
    exit_code = call_and_report(
        verb="re-format the GDScripts" if overwrite else "check the formatting of the GDScripts",
        cmd=[sys.executable, "-m", "gdtoolkit.formatter"]
        + ([] if overwrite else ["--check"])
        + ["scenes", "tests/godot"],
        cwd=REPO_ROOT,
    )
    if exit_code != 0:
        return 1

    exit_code = call_and_report(
        verb="re-format the C# code" if overwrite else "check the formatting of the C# code",
        cmd=["dotnet", "format", "SplashNSplat.sln"]
        + ([] if overwrite else ["--verify-no-changes"]),
        cwd=REPO_ROOT,
    )
    if exit_code != 0:
        return 1

    exit_code = call_and_report(
        verb=(
            "re-format the Python code" if overwrite else "check the formatting of the Python code"
        ),
        cmd=[sys.executable, "-m", "black", "--line-length", "100"]
        + ([] if overwrite else ["--check"])
        + ["dev"],
        cwd=REPO_ROOT,
    )
    if exit_code != 0:
        return 1

    return 0


def check_scripts(godot: str, jobs: int) -> int:
    """Type-check every GDScript in parallel."""
    scripts = sorted(
        path
        for directory in ("scenes", "tests/godot")
        for path in (REPO_ROOT / directory).rglob("*.gd")
    )
    print(f"Type-checking {len(scripts)} GDScript(s)...", flush=True)

    def check(script: pathlib.Path) -> Tuple[pathlib.Path, int, str]:
        code, output, _ = run_captured(
            [godot, "--headless", "--path", ".", "--check-only", "--script", str(script)],
            timeout=120.0,
        )
        return script, code, output

    failed: List[pathlib.Path] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as executor:
        for script, code, output in executor.map(check, scripts):
            if code != 0 or GODOT_ERROR_RE.search(output):
                failed.append(script)
                print(f"--- {script.relative_to(REPO_ROOT)}\n{output}", file=sys.stderr)

    if failed:
        print(f"Failed to type-check {len(failed)} GDScript(s).", file=sys.stderr)
        return 1

    return 0


def run_godot_tests(godot: str, jobs: int, only: Optional[Sequence[str]], verbose: bool) -> int:
    """Run the Godot test scripts of tests/godot/ in parallel."""
    tests = sorted((REPO_ROOT / "tests" / "godot").glob("test_*.gd"))
    if only:
        tests = [test for test in tests if any(name in test.name for name in only)]

    print(f"Running {len(tests)} Godot test(s)...", flush=True)

    def run_test(test: pathlib.Path) -> Tuple[pathlib.Path, int, str, float]:
        # NOTE (mristin):
        # With the fixed frame rate, Godot simulates the game time as fast as it
        # can, instead of waiting for the wall clock.
        code, output, duration = run_captured(
            [
                godot,
                "--headless",
                "--fixed-fps",
                "60",
                "--disable-vsync",
                "--max-fps",
                "0",
                "--path",
                ".",
                "--script",
                str(test),
            ],
            timeout=300.0,
        )
        return test, code, output, duration

    failed: List[pathlib.Path] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as executor:
        for test, code, output, duration in executor.map(run_test, tests):
            passed = code == 0 and "RESULT: OK" in output and not GODOT_ERROR_RE.search(output)
            if not passed:
                failed.append(test)

            print(
                f"  {'passed' if passed else 'FAILED'} {test.relative_to(REPO_ROOT)} "
                f"in {duration:.1f} s",
                flush=True,
            )
            if not passed or verbose:
                print(output)

    if failed:
        print(f"Failed {len(failed)} of {len(tests)} Godot test(s).", file=sys.stderr)
        return 1

    return 0


def main() -> int:
    """Execute the entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--overwrite",
        help="Try to automatically fix the offending files (e.g., by re-formatting).",
        action="store_true",
    )
    parser.add_argument(
        "--select",
        help=(
            "If set, only the selected steps are executed. "
            "This is practical if some of the steps failed and you want to "
            "fix them in isolation. "
            "The steps are given as a space-separated list of: "
            + " ".join(value.value for value in Step)
        ),
        metavar="",
        nargs="+",
        choices=[value.value for value in Step],
    )
    parser.add_argument(
        "--skip",
        help=(
            "If set, skips the specified steps. "
            "This is practical if some of the steps passed and "
            "you want to fix the remainder in isolation. "
            "The steps are given as a space-separated list of: "
            + " ".join(value.value for value in Step)
        ),
        metavar="",
        nargs="+",
        choices=[value.value for value in Step],
    )
    parser.add_argument(
        "--godot",
        help=(
            "Path to the Godot 4.6 .NET executable; "
            "if not set, we use the GODOT environment variable, then godot on the path"
        ),
    )
    parser.add_argument(
        "--only",
        help="Run only the Godot tests whose file name contains one of these names",
        metavar="",
        nargs="+",
    )
    parser.add_argument(
        "--jobs",
        help="How many Godot processes to run in parallel",
        type=int,
        default=os.cpu_count() or 2,
    )
    parser.add_argument(
        "--verbose",
        help="Print the output of the passed Godot tests as well",
        action="store_true",
    )
    args = parser.parse_args()

    overwrite = bool(args.overwrite)

    selects = [Step(value) for value in args.select] if args.select is not None else list(Step)
    skips = [Step(value) for value in args.skip] if args.skip is not None else []
    steps = [step for step in Step if step in selects and step not in skips]

    godot: Optional[str] = None
    if any(step in steps for step in (Step.IMPORT, Step.CHECK_SCRIPTS, Step.GODOT_TEST)):
        godot = find_godot(args.godot)
        if godot is None:
            print(
                "Could not find Godot. Pass --godot, set the GODOT environment variable, "
                "or put godot on the path. See CONTRIBUTING.md.",
                file=sys.stderr,
            )
            return 1

    start = time.perf_counter()

    for step in Step:
        if step not in steps:
            print(f"Skipped {step.value}.")
            continue

        if step == Step.REFORMAT:
            exit_code = reformat(overwrite)

        elif step == Step.LINT:
            # NOTE (mristin):
            # gdlint checks the GDScript style guide: the naming, the order of
            # the definitions, the line length etc. Godot itself type-checks the
            # scripts in the check-scripts step.
            print("Linting the GDScripts...")
            exit_code = call_and_report(
                verb="lint the GDScripts",
                cmd=[sys.executable, "-m", "gdtoolkit.linter", "scenes", "tests/godot"],
                cwd=REPO_ROOT,
            )

        elif step == Step.DOTNET_TEST:
            print("Running the C# unit tests...")
            exit_code = call_and_report(
                verb="run the C# unit tests",
                cmd=["dotnet", "test", "SplashNSplat.sln", "--nologo"],
                cwd=REPO_ROOT,
            )

        elif step == Step.BUILD:
            print("Building the C# part of the game, so that Godot can load it...")
            exit_code = call_and_report(
                verb="build the C# part of the game",
                cmd=["dotnet", "build", "SplashNSplat.csproj", "--nologo"],
                cwd=REPO_ROOT,
            )

        elif step == Step.IMPORT:
            assert godot is not None
            # NOTE (mristin):
            # The import also refreshes the cache of the global class names, which
            # the type-checks and the tests rely on.
            print("Importing the project with Godot...")
            exit_code = call_and_report(
                verb="import the project with Godot",
                cmd=[godot, "--headless", "--path", ".", "--import"],
                cwd=REPO_ROOT,
            )

        elif step == Step.CHECK_SCRIPTS:
            assert godot is not None
            exit_code = check_scripts(godot, args.jobs)

        elif step == Step.GODOT_TEST:
            assert godot is not None
            exit_code = run_godot_tests(godot, args.jobs, args.only, args.verbose)

        else:
            raise AssertionError(f"Unhandled step: {step}")

        if exit_code != 0:
            return 1

    print(f"All the selected steps passed in {time.perf_counter() - start:.1f} s.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
