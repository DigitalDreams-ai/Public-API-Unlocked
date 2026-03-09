#!/usr/bin/env python3
"""
Dependency hygiene gate for PublicApi-Unlocked.

Fails CI when:
1) `Shulman-Core` is reintroduced in `cumulusci.yml`.
2) Banned Shulman-Core coupling tokens are found in `force-app/main/default`.
"""

from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
FORCE_APP_ROOT = REPO_ROOT / "force-app" / "main" / "default"
CUMULUSCI_FILE = REPO_ROOT / "cumulusci.yml"

BANNED_TOKENS = [
    "Shulman-Core",
    "Nimba-Solutions/Shulman-Core",
]


def scan_force_app_for_banned_tokens() -> list[str]:
    violations: list[str] = []
    if not FORCE_APP_ROOT.exists():
        return [f"Missing metadata root: {FORCE_APP_ROOT}"]

    for path in FORCE_APP_ROOT.rglob("*"):
        if not path.is_file():
            continue
        try:
            content = path.read_text(encoding="utf-8", errors="ignore")
        except Exception as exc:
            violations.append(f"{path.relative_to(REPO_ROOT)}: unable to read ({exc})")
            continue

        for token in BANNED_TOKENS:
            if token in content:
                violations.append(f"{path.relative_to(REPO_ROOT)} contains banned token `{token}`")
    return violations


def main() -> int:
    violations: list[str] = []

    if not CUMULUSCI_FILE.exists():
        violations.append(f"Missing {CUMULUSCI_FILE.relative_to(REPO_ROOT)}")
    else:
        cumulusci_text = CUMULUSCI_FILE.read_text(encoding="utf-8", errors="ignore")
        if "Nimba-Solutions/Shulman-Core" in cumulusci_text:
            violations.append("`cumulusci.yml` references `Nimba-Solutions/Shulman-Core`.")
        if "package_name: Shulman-Core" in cumulusci_text:
            violations.append("`cumulusci.yml` references `Shulman-Core`.")

    violations.extend(scan_force_app_for_banned_tokens())

    if violations:
        print("Dependency hygiene check failed:")
        for violation in violations:
            print(f"- {violation}")
        return 1

    print("Dependency hygiene check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
