#!/usr/bin/env python3
# ruff: noqa: T201 allow print statements
"""Promote a TestFlight build to App Store review.

Finds the newest valid build for the given marketing version, ensures an App
Store version exists for it, attaches the build, enables phased release, and
submits for review. Requires PyJWT + cryptography (installed by the workflow).

Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (PEM), BUNDLE_ID, VERSION.
"""

from __future__ import annotations

import os
import sys
import json
import time
import urllib.error
import urllib.request
from typing import Any

import jwt

BASE = "https://api.appstoreconnect.apple.com"


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def make_token() -> str:
    return jwt.encode(
        {
            "iss": os.environ["ASC_ISSUER_ID"],
            "iat": int(time.time()) - 60,
            "exp": int(time.time()) + 15 * 60,
            "aud": "appstoreconnect-v1",
        },
        os.environ["ASC_KEY_P8"],
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"]},
    )


def request(method: str, path: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
    req = urllib.request.Request(
        BASE + path,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={
            "Authorization": f"Bearer {make_token()}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        fail(f"{method} {path} -> {error.code}: {detail}")
        raise  # unreachable


def main() -> None:
    bundle_id = os.environ.get("BUNDLE_ID", "com.posthog.ios")
    version = os.environ["VERSION"]

    apps = request("GET", f"/v1/apps?filter[bundleId]={bundle_id}")["data"]
    if not apps:
        fail(f"no App Store Connect app for bundle id {bundle_id}")
    app_id = apps[0]["id"]
    print(f"app: {app_id} ({bundle_id})")

    builds = request(
        "GET",
        f"/v1/builds?filter[app]={app_id}"
        f"&filter[preReleaseVersion.version]={version}"
        "&filter[processingState]=VALID&sort=-uploadedDate&limit=1",
    )["data"]
    if not builds:
        fail(f"no processed build for marketing version {version} — is TestFlight processing done?")
    build_id = builds[0]["id"]
    print(f"build: {build_id} (#{builds[0]['attributes']['version']})")

    versions = request(
        "GET",
        f"/v1/apps/{app_id}/appStoreVersions?filter[versionString]={version}&limit=1",
    )["data"]
    if versions:
        version_id = versions[0]["id"]
        print(f"app store version exists: {version_id}")
    else:
        created = request(
            "POST",
            "/v1/appStoreVersions",
            {
                "data": {
                    "type": "appStoreVersions",
                    "attributes": {"platform": "IOS", "versionString": version},
                    "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
                }
            },
        )
        version_id = created["data"]["id"]
        print(f"created app store version: {version_id}")

    request(
        "PATCH",
        f"/v1/appStoreVersions/{version_id}/relationships/build",
        {"data": {"type": "builds", "id": build_id}},
    )
    print("build attached")

    phased = request("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionPhasedRelease").get("data")
    if not phased:
        request(
            "POST",
            "/v1/appStoreVersionPhasedReleases",
            {
                "data": {
                    "type": "appStoreVersionPhasedReleases",
                    "attributes": {"phasedReleaseState": "INACTIVE"},
                    "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}},
                }
            },
        )
        print("phased release enabled")

    submission = request(
        "POST",
        "/v1/reviewSubmissions",
        {
            "data": {
                "type": "reviewSubmissions",
                "attributes": {"platform": "IOS"},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        },
    )
    submission_id = submission["data"]["id"]
    request(
        "POST",
        "/v1/reviewSubmissionItems",
        {
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
                    "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
                },
            }
        },
    )
    request(
        "PATCH",
        f"/v1/reviewSubmissions/{submission_id}",
        {
            "data": {
                "type": "reviewSubmissions",
                "id": submission_id,
                "attributes": {"submitted": True},
            }
        },
    )
    print(f"submitted {version} for review (submission {submission_id})")


if __name__ == "__main__":
    main()
