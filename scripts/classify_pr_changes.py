#!/usr/bin/env python3
"""Print whether a PR needs full tests for NUL-delimited git diff paths."""

import os
import sys


LIGHTWEIGHT_FILES = frozenset({
    "AGENTS.md",
    "README.md",
    "ROADMAP.md",
    ".github/pull_request_template.md",
})
ISSUE_TEMPLATE_PREFIX = ".github/ISSUE_TEMPLATE/"


def is_lightweight_path(path):
    if path in LIGHTWEIGHT_FILES:
        return True
    return (path.startswith(ISSUE_TEMPLATE_PREFIX)
            and all(part not in ("", ".", "..") for part in path.split("/")))


def main():
    changed_paths = sys.stdin.buffer.read()
    if not changed_paths or not changed_paths.endswith(b"\0"):
        print("true")
        return

    paths = changed_paths[:-1].split(b"\0")
    run_full = any(not path or not is_lightweight_path(os.fsdecode(path))
                   for path in paths)
    print("true" if run_full else "false")


if __name__ == "__main__":
    main()
