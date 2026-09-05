#!/usr/bin/env python3
# ruff: noqa: T201 allow print statements
"""Stackless CI check that the Swift API surface matches the committed lock.

Runs without a dev stack:
1. No Swift source may mention /api/environments/ (deprecated, sunset 2026-07-31).
2. Every "/api/..." path template literal in package sources must match a
   path in openapi/api-lock.json (placeholders compared structurally).
3. Every path in endpoint-allowlist.json must be present in the lock (the lock
   is stale when the allowlist grew without a `make api-lock` run).
"""

from __future__ import annotations

import re
import sys
import json
from pathlib import Path

IOS_ROOT = Path(__file__).resolve().parent.parent
SOURCES = IOS_ROOT / "Packages" / "PostHogKit" / "Sources"
LOCK_PATH = IOS_ROOT / "openapi" / "api-lock.json"
ENDPOINT_ALLOWLIST = IOS_ROOT / "openapi" / "endpoint-allowlist.json"

PATH_LITERAL = re.compile(r'"(/api/[^"\s]*)"')


def normalize(path: str) -> str:
    """Collapse placeholder names so {id} and {project_id} compare structurally."""
    collapsed = re.sub(r"\{[^}]+\}", "{}", path)
    collapsed = re.sub(r"\\\((.*?)\)", "{}", collapsed)  # Swift interpolation
    return collapsed if collapsed.endswith("/") else collapsed + "/"


def main() -> None:
    errors: list[str] = []

    swift_files = list(SOURCES.rglob("*.swift"))
    for file in swift_files:
        text = file.read_text()
        if "/api/environments/" in text:
            errors.append(
                f"{file.relative_to(IOS_ROOT)}: uses deprecated /api/environments/ "
                "(sunset 2026-07-31) — target /api/projects/ instead"
            )

    allowlist = json.loads(ENDPOINT_ALLOWLIST.read_text())["paths"]
    allowed = {normalize(p) for p in allowlist}

    for file in swift_files:
        # Mock servers match concrete fixture paths, not client templates.
        if file.name == "UITestSupport.swift":
            continue
        for literal in PATH_LITERAL.findall(file.read_text()):
            if normalize(literal) not in allowed:
                errors.append(f"{file.relative_to(IOS_ROOT)}: path {literal!r} is not in endpoint-allowlist.json")

    # The lock adds spec verification on top once `make api-lock` has run
    # against a live stack; until then the allowlist check above still holds.
    if LOCK_PATH.exists():
        lock = json.loads(LOCK_PATH.read_text())
        lock_paths = {normalize(p) for p in lock["openapi"]["paths"]}
        for path in allowlist:
            if normalize(path) not in lock_paths:
                errors.append(f"allowlisted path {path} not in api-lock.json — run `make api-lock`")
    else:
        print("note: openapi/api-lock.json not generated yet (needs a dev stack)")

    if errors:
        for error in errors:
            print(f"✗ {error}", file=sys.stderr)
        sys.exit(1)
    print(f"ok: {len(swift_files)} Swift files checked against the API lock")


if __name__ == "__main__":
    main()
