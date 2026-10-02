#!/usr/bin/env python3
"""Classify a build run's recorded main-push range; uncertainty requires release."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


SHA = re.compile(r"[0-9a-f]{40}\Z")
CLASSIFIER = Path(__file__).with_name("classify_release_changes.py")


def is_commit(sha):
    return subprocess.run(
        ["git", "cat-file", "-e", f"{sha}^{{commit}}"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0


def needs_release(provenance_path, source_sha, run_head_sha, trigger_event):
    if trigger_event != "push" or not SHA.fullmatch(source_sha) or source_sha != run_head_sha:
        return True
    try:
        if provenance_path.stat().st_size > 4096:
            return True
        record = json.loads(provenance_path.read_text(encoding="utf-8"))
        if not isinstance(record, dict) or record.get("event") != "push":
            return True
        previous_sha = record.get("previous_sha")
        if record.get("source_sha") != source_sha or not isinstance(previous_sha, str):
            return True
        if not SHA.fullmatch(previous_sha) or not is_commit(previous_sha) or not is_commit(source_sha):
            return True
        if subprocess.run(
            ["git", "merge-base", "--is-ancestor", previous_sha, source_sha],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        ).returncode != 0:
            return True
        changed = subprocess.run(
            ["git", "diff", "--name-only", "--no-renames", "-z",
             previous_sha, source_sha, "--"],
            capture_output=True, check=True,
        ).stdout
        result = subprocess.run(
            [sys.executable, str(CLASSIFIER)], input=changed,
            capture_output=True, check=True,
        ).stdout
        return result != b"false\n"
    except (OSError, ValueError, UnicodeError, subprocess.SubprocessError):
        return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--provenance", type=Path, required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--run-head-sha", required=True)
    parser.add_argument("--trigger-event", required=True)
    args = parser.parse_args()
    print("true" if needs_release(
        args.provenance, args.source_sha, args.run_head_sha,
        args.trigger_event,
    ) else "false")


if __name__ == "__main__":
    main()
