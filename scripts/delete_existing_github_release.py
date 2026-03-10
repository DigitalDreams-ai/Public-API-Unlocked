#!/usr/bin/env python3
import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


def build_headers(token: str) -> dict:
    return {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "publicapi-unlocked-release-cleanup",
    }


def request_json(method: str, url: str, headers: dict) -> tuple[int, dict | None]:
    request = urllib.request.Request(url, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request) as response:
            body = response.read().decode("utf-8")
            return response.status, json.loads(body) if body else None
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8")
        if error.code == 404:
            return 404, None
        raise RuntimeError(f"GitHub API {method} {url} failed: {error.code} {body}") from error


def request_no_content(method: str, url: str, headers: dict) -> int:
    request = urllib.request.Request(url, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request) as response:
            response.read()
            return response.status
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8")
        if error.code == 404:
            return 404
        raise RuntimeError(f"GitHub API {method} {url} failed: {error.code} {body}") from error


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Delete an existing beta GitHub release/tag so release_unlocked_beta can recreate it."
    )
    parser.add_argument("--version", required=True)
    parser.add_argument("--tag-prefix", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    repository = os.getenv("GITHUB_REPOSITORY")
    token = os.getenv("GITHUB_TOKEN") or os.getenv("GH_TOKEN")

    if not repository:
        print("GITHUB_REPOSITORY not set. Skipping beta release cleanup.")
        return 0
    if not token:
        print("GITHUB_TOKEN/GH_TOKEN not set. Skipping beta release cleanup.")
        return 0

    tag = f"{args.tag_prefix}{args.version}"
    if not tag.startswith("beta/"):
        print(f"Refusing to clean non-beta tag: {tag}")
        return 1

    headers = build_headers(token)
    encoded_tag = urllib.parse.quote(tag, safe="")
    release_url = f"https://api.github.com/repos/{repository}/releases/tags/{encoded_tag}"
    status, release = request_json("GET", release_url, headers)
    if status == 404 or not release:
        print(f"No existing release for tag {tag}.")
        return 0

    release_id = release["id"]
    if not release.get("prerelease", False):
        print(f"Refusing to delete non-prerelease release for tag {tag}.")
        return 1

    delete_release_url = f"https://api.github.com/repos/{repository}/releases/{release_id}"
    delete_tag_url = f"https://api.github.com/repos/{repository}/git/refs/tags/{encoded_tag}"

    if args.dry_run:
        print(f"Would delete prerelease {tag} (release id {release_id}) and tag ref.")
        return 0

    release_status = request_no_content("DELETE", delete_release_url, headers)
    tag_status = request_no_content("DELETE", delete_tag_url, headers)
    print(
        f"Deleted existing prerelease/tag for {tag}. "
        f"release_status={release_status}, tag_status={tag_status}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
