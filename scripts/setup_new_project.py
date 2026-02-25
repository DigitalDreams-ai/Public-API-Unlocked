#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

SEARCH_DIRS = ["force-app", "datasets", "robot", "category", ".cci", "scripts"]
ROOT_FILES = [Path(".gitignore"), Path("sfdx-project.json"), Path("README.md"), Path("cumulusci.yml")]
SKIP_PARTS = ("__pycache__", ".pyc", "node_modules")
TOKEN_NAME = "__PROJECT_NAME__"
TOKEN_LABEL = "__PROJECT_LABEL__"
BACKTICK_RE = re.compile(r"(`{1,})(.*?)\1", re.DOTALL)
EXCLUDE = {Path("scripts") / "setup_new_project.py", Path("scripts") / "setup_new_script.py"}
INIT_MARKER = Path(".project_initialized")
THIS_FILE = Path(__file__).resolve()


def _files():
    seen = set()
    skip = lambda p: (
        p in EXCLUDE
        or p.resolve() == THIS_FILE
        or any(x in str(p) for x in SKIP_PARTS)
        or p.name == ".git"
        or any(parent.name == ".git" for parent in p.parents)
    )
    for root in map(Path, SEARCH_DIRS):
        if root.exists():
            for f in root.rglob("*"):
                if f.is_file() and f not in seen and not skip(f):
                    seen.add(f)
                    yield f
    for f in ROOT_FILES:
        if f.exists() and f not in seen:
            seen.add(f)
            yield f
    for extra in (Path("orgs"), Path(".cci") / "snapshot"):
        if extra.exists():
            for f in extra.glob("*.json"):
                if f not in seen:
                    seen.add(f)
                    yield f


def _replace_readme(text, rep):
    out, pos = [], 0
    for m in BACKTICK_RE.finditer(text):
        out += [rep(text[pos : m.start()]), m.group(0)]
        pos = m.end()
    out.append(rep(text[pos:]))
    return "".join(out)


def _repo_slug():
    env_repo = (os.getenv("GITHUB_REPOSITORY") or "").strip()
    if "/" in env_repo:
        return env_repo
    try:
        remote = subprocess.check_output(["git", "config", "--get", "remote.origin.url"], text=True).strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    m = re.search(r"github\.com[:/](?P<owner>[^/]+)/(?P<repo>[^/]+?)(?:\.git)?$", remote)
    return f"{m.group('owner')}/{m.group('repo')}" if m else None


def _which(*names):
    for name in names:
        path = shutil.which(name)
        if path:
            return path
    return None


def _mask_secret(value):
    if not value:
        return ""
    if len(value) <= 20:
        return "*" * len(value)
    return f"{value[:14]}...{value[-14:]} (len={len(value)})"


def _set_dev_hub_secret(dev_hub_org, repo_slug):
    sf_bin = _which("sf", "sf.cmd", "sfdx", "sfdx.cmd")
    if not sf_bin:
        print("[WARNING] Salesforce CLI (sf) not found.")
        return False
    sf_cmd = (
        [sf_bin, "org", "display", "-o", dev_hub_org, "--verbose", "--json"]
        if Path(sf_bin).name.lower().startswith("sf")
        else [sf_bin, "force:org:display", "-u", dev_hub_org, "--verbose", "--json"]
    )
    sf_res = subprocess.run(sf_cmd, text=True, capture_output=True)
    if sf_res.returncode != 0:
        msg = (sf_res.stderr or sf_res.stdout or "").strip()
        print("[WARNING] sf org display failed.")
        if msg:
            print(msg)
        return False
    raw = (sf_res.stdout or "").strip()
    try:
        auth_url = (json.loads(raw).get("result") or {}).get("sfdxAuthUrl")
    except json.JSONDecodeError:
        m = re.search(r'force://[^"\s]+', raw)
        auth_url = m.group(0) if m else None
    if not auth_url:
        print("[WARNING] Could not find sfdxAuthUrl in sf output.")
        return False
    auth_url = auth_url.strip().rstrip('"}\\]')
    if "@https://" in auth_url:
        auth_url = auth_url.replace("@https://", "@")
    elif "@http://" in auth_url:
        auth_url = auth_url.replace("@http://", "@")
    print(f"[INFO] sfdxAuthUrl preview: {_mask_secret(auth_url)}")
    gh_bin = _which("gh", "gh.exe", "gh.cmd")
    if not gh_bin:
        print("[WARNING] GitHub CLI (gh) not found.")
        return False
    rc = subprocess.run([gh_bin, "secret", "set", "DEV_HUB_AUTH_URL", "--repo", repo_slug, "--body", auth_url]).returncode
    if rc != 0:
        print("[WARNING] Failed to set GitHub secret DEV_HUB_AUTH_URL.")
        return False
    list_res = subprocess.run([gh_bin, "secret", "list", "--repo", repo_slug], text=True, capture_output=True)
    if list_res.returncode == 0:
        line = next((l for l in list_res.stdout.splitlines() if l.startswith("DEV_HUB_AUTH_URL")), "")
        if line:
            print(f"[OK] Set DEV_HUB_AUTH_URL for {repo_slug}: {line}")
        else:
            print(f"[OK] Set DEV_HUB_AUTH_URL for {repo_slug} (not found in list output).")
    else:
        print(f"[OK] Set DEV_HUB_AUTH_URL for {repo_slug} (secret list check failed).")
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Replace __PROJECT_NAME__ and __PROJECT_LABEL__ in filenames and file contents."
    )
    parser.add_argument("--repo-name", type=str, help="Repository name (e.g. 'Standard-Unlocked-Shulman')")
    parser.add_argument("--non-interactive", action="store_true", help="No prompts; use defaults")
    parser.add_argument("--project-name", type=str, help="Project name (overrides derivation)")
    parser.add_argument("--package-name", type=str, help="Package name (overrides derivation)")
    parser.add_argument("--name-managed", type=str, help="Name managed (overrides derivation)")
    parser.add_argument("--git-commit-push", action="store_true", help="Commit and push changes to GitHub")
    parser.add_argument("--commit-message", type=str, default="Replace project tokens", help="Git commit message")
    parser.add_argument("--set-dev-hub-secret", action="store_true", help="Set DEV_HUB_AUTH_URL repo secret with sf/gh")
    parser.add_argument("--dev-hub-org", type=str, help="Dev Hub org alias/username for sf org display")
    parser.add_argument("--github-repo", type=str, help="GitHub repo as owner/name for gh secret set")
    args = parser.parse_args()

    repo_name = args.repo_name or os.getenv("GITHUB_REPOSITORY_NAME") or os.getenv("REPO_NAME") or Path.cwd().name
    non_interactive = args.non_interactive or os.getenv("CI") == "true"
    repo_only = (os.getenv("GITHUB_REPOSITORY") or "").lower().split("/")[-1]

    if non_interactive and repo_only in ("__project_name__", "__project_label__"):
        print("ERROR: Template Repository Protection")
        print("\nThis script must not run on the template repository in CI.")
        print(f"Detected: {os.getenv('GITHUB_REPOSITORY', 'unknown')}\n")
        sys.exit(1)

    if repo_name == "Standard-Unlocked-Shulman":
        print("WARNING: Template Repository Detected")
        print("\nThis appears to be the template repo. Run in a new repo created from the template.")
        print("To run here anyway: python scripts/setup_new_project.py --repo-name 'Your-Project-Name'\n")
        if non_interactive:
            print("Non-interactive mode; exiting to avoid changes on the template repo.")
            sys.exit(1)
        if input("Continue anyway? (y/n): ").strip().lower() != "y":
            print("Cancelled.")
            sys.exit(0)

    if args.project_name and args.package_name and args.name_managed:
        project_name, package_name, name_managed = args.project_name, args.package_name, args.name_managed
    else:
        project_name = repo_name.replace("-", " ").replace("_", " ") if repo_name else ""
        package_name = project_name.replace(" ", "")
        name_managed = project_name

    while True:
        if not project_name:
            if non_interactive:
                print("Error: Provide --repo-name or set explicit project values.")
                sys.exit(1)
            project_name = input("Project Name (e.g. 'Shulman Intake Platform'): ").strip()
            if not project_name:
                print("Error: Project name is required.")
                continue
            package_name = project_name.replace(" ", "")
            name_managed = project_name
            print(f"\nDerived: Package Name = {package_name}, Name Managed = {name_managed}")
        print(f"Project Name: {project_name}\nPackage Name: {package_name}\nName Managed: {name_managed}")
        if non_interactive or input("\nUse these values? (y/n): ").strip().lower() == "y":
            break
        project_name = ""

    want_git = args.git_commit_push if non_interactive else (
        input("\nCommit and push to GitHub after success? (y/n): ").strip().lower() == "y"
    )
    want_secret = args.set_dev_hub_secret if non_interactive else (
        input("Set DEV_HUB_AUTH_URL GitHub secret now? (y/n): ").strip().lower() == "y"
    )
    dev_hub_org = args.dev_hub_org
    if want_secret and not dev_hub_org and not non_interactive:
        dev_hub_org = input("Dev Hub org alias/username for sf org display: ").strip()

    label_value = name_managed.replace(" ", "-")
    rep = lambda t: t.replace(TOKEN_NAME, package_name).replace(TOKEN_LABEL, label_value)
    renamed = updated = 0

    for root in map(Path, SEARCH_DIRS):
        if not root.exists():
            continue
        dirs = [p for p in root.rglob("*") if p.is_dir() and (TOKEN_NAME in p.name or TOKEN_LABEL in p.name)]
        for p in sorted(dirs, key=lambda x: len(x.parts), reverse=True):
            new_name = p.name.replace(TOKEN_NAME, package_name).replace(TOKEN_LABEL, label_value)
            new_path = p.parent / new_name
            if new_path.exists() and new_path != p:
                print(f"[WARNING] Target exists, skipping: {new_path}")
                continue
            try:
                p.rename(new_path)
                renamed += 1
            except OSError as e:
                print(f"[WARNING] Could not rename {p}: {e}")

        for f in root.rglob("*"):
            if f.is_file() and TOKEN_NAME in f.name:
                new_path = f.parent / f.name.replace(TOKEN_NAME, package_name)
                if new_path.exists() and new_path != f:
                    print(f"[WARNING] Target exists, skipping: {new_path}")
                    continue
                try:
                    f.rename(new_path)
                    renamed += 1
                except OSError as e:
                    print(f"[WARNING] Could not rename {f}: {e}")

    remaining = []
    for f in _files():
        try:
            text = f.read_text(encoding="utf-8", errors="ignore")
        except (UnicodeDecodeError, PermissionError, OSError):
            continue
        new = _replace_readme(text, rep) if f.name.lower() == "readme.md" else rep(text)
        if new != text:
            try:
                f.write_text(new, encoding="utf-8")
                updated += 1
            except OSError as e:
                print(f"[WARNING] Could not update {f}: {e}")
        if TOKEN_NAME in f.name or TOKEN_LABEL in f.name:
            remaining.append((f, "filename"))
        scan = BACKTICK_RE.sub("", new) if f.name.lower() == "readme.md" else new
        if TOKEN_NAME in scan:
            remaining.append((f, TOKEN_NAME))
        if TOKEN_LABEL in scan:
            remaining.append((f, TOKEN_LABEL))

    print(f"\n[OK] Renamed {renamed} item(s), updated {updated} file(s)")
    if remaining:
        print(f"[WARNING] {len(remaining)} file(s) still have tokens:")
        for path, loc in remaining:
            print(f"  - {path} ({loc})")
        print("\nReplace these manually if needed.")
    else:
        print("[OK] No remaining tokens.")
        if not INIT_MARKER.exists():
            INIT_MARKER.parent.mkdir(parents=True, exist_ok=True)
            INIT_MARKER.write_text("initialized\n", encoding="utf-8")
            print(f"[OK] Created {INIT_MARKER}")

    if want_git and not remaining:
        for cmd, label in (
            (["git", "add", "."], "git add"),
            (["git", "commit", "-m", args.commit_message], "git commit"),
            (["git", "push"], "git push"),
        ):
            if subprocess.run(cmd).returncode != 0:
                print(f"[WARNING] {label} failed; stopping.")
                break
    elif want_git and remaining:
        print("[WARNING] Skipping git commit/push because tokens remain.")

    if want_secret and not remaining:
        if not dev_hub_org:
            print("[WARNING] Skipping secret setup: missing Dev Hub org.")
            return
        repo_slug = args.github_repo or _repo_slug()
        if not repo_slug and not non_interactive:
            repo_slug = input("GitHub repo (owner/name): ").strip()
        if not repo_slug:
            print("[WARNING] Skipping secret setup: could not resolve repo.")
            return
        _set_dev_hub_secret(dev_hub_org, repo_slug)
    elif want_secret and remaining:
        print("[WARNING] Skipping secret setup because tokens remain.")


if __name__ == "__main__":
    main()
