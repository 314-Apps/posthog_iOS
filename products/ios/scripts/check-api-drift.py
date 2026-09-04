#!/usr/bin/env python3
"""Stackless CI check that the Swift API surface matches the committed lock.

Runs without a dev stack:
1. No Swift source may mention /api/environments/ (deprecated, sunset 2026-07-31).
2. Every "/api/..." path template literal in PostHogAPI/Endpoints must match a
   path in openapi/api-lock.json (placeholders compared structurally).
3. Every path in endpoint-allowlist.json must be present in the lock (the lock
   is stale when the allowlist grew without a `make api-lock` run).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

IOS_ROOT = Path(__file__).resolve().parent.parent
SOURCES = IOS_ROOT / "Packages" / "PostHogKit" / "Sources"
ENDPOINTS_DIR = SOURCES / "PostHogAPI" / "Endpoints"
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

    if not LOCK_PATH.exists():
        errors.append("openapi/api-lock.json missing — run `make api-lock`")
    else:
        lock = json.loads(LOCK_PATH.read_text())
        lock_paths = {normalize(p) for p in lock["openapi"]["paths"]}

        allowlist = json.loads(ENDPOINT_ALLOWLIST.read_text())["paths"]
        for path in allowlist:
            if normalize(path) not in lock_paths:
                errors.append(
                    f"allowlisted path {path} not in api-lock.json — run `make api-lock`"
                )

        if ENDPOINTS_DIR.exists():
            for file in ENDPOINTS_DIR.rglob("*.swift"):
                for literal in PATH_LITERAL.findall(file.read_text()):
                    if normalize(literal) not in lock_paths:
                        errors.append(
                            f"{file.relative_to(IOS_ROOT)}: path {literal!r} is not in "
                            "api-lock.json — add it to endpoint-allowlist.json and run "
                            "`make api-lock`"
                        )

    if errors:
        for error in errors:
            print(f"✗ {error}", file=sys.stderr)
        sys.exit(1)
    print(f"ok: {len(swift_files)} Swift files checked against the API lock")


if __name__ == "__main__":
    main()
