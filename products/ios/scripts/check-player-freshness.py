#!/usr/bin/env python3
# ruff: noqa: T201 allow print statements
"""Fail when the committed replay player is older than its source.

The player is built from `player/` and the result is committed, because iOS CI
checks out only this tree and the build needs `common/replay-shared`, which is
outside it. CI therefore cannot rebuild the player to compare. It can, however,
notice that the source moved and the artifact did not, which is the mistake this
catches: editing `player/src` and forgetting `make player` leaves a stale player
in the app with nothing to say so.
"""

from __future__ import annotations

import sys
import json
import hashlib
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
PLAYER = ROOT / "player"
ARTIFACT = ROOT / "Packages/PostHogKit/Sources/FeatureReplay/Resources/player.html"
STAMP = PLAYER / "build-stamp.json"

# Everything whose change alters the built player.
SOURCES = ["build.mjs", "package.json", "package-lock.json"]
SOURCE_DIRS = ["src"]


def source_digest() -> str:
    digest = hashlib.sha256()
    paths: list[pathlib.Path] = []
    for name in SOURCES:
        path = PLAYER / name
        if path.exists():
            paths.append(path)
    for name in SOURCE_DIRS:
        paths.extend(sorted(p for p in (PLAYER / name).rglob("*") if p.is_file()))
    for path in sorted(paths, key=lambda p: p.relative_to(PLAYER).as_posix()):
        digest.update(path.relative_to(PLAYER).as_posix().encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


def artifact_digest() -> str:
    return hashlib.sha256(ARTIFACT.read_bytes()).hexdigest()


def write_stamp() -> None:
    STAMP.write_text(json.dumps({"sources": source_digest(), "artifact": artifact_digest()}, indent=2) + "\n")
    print(f"wrote {STAMP.relative_to(ROOT)}")


def check() -> int:
    if not ARTIFACT.exists():
        print(f"✗ {ARTIFACT.relative_to(ROOT)} is missing — run `make player`", file=sys.stderr)
        return 1
    if not STAMP.exists():
        print(f"✗ {STAMP.relative_to(ROOT)} is missing — run `make player`", file=sys.stderr)
        return 1

    stamp = json.loads(STAMP.read_text())
    errors = []
    if stamp.get("sources") != source_digest():
        errors.append("the player source changed but the player was not rebuilt")
    if stamp.get("artifact") != artifact_digest():
        errors.append("the bundled player does not match the one that was built")

    if errors:
        for error in errors:
            print(f"✗ {error}", file=sys.stderr)
        print("  run `make player` and commit the result", file=sys.stderr)
        return 1

    print("ok: the bundled replay player matches its source")
    return 0


if __name__ == "__main__":
    if "--write" in sys.argv:
        write_stamp()
        sys.exit(0)
    sys.exit(check())
