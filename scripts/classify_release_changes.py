#!/usr/bin/env python3
"""Print whether changed paths require a production release (NUL-delimited input)."""

import os
import sys


NEUTRAL_FILES = frozenset({
    "AGENTS.md",
    "README.md",
    "ROADMAP.md",
    ".github/pull_request_template.md",
})
ISSUE_TEMPLATE_PREFIX = ".github/ISSUE_TEMPLATE/"


def is_release_neutral(path):
    if path in NEUTRAL_FILES:
        return True
    return (path.startswith(ISSUE_TEMPLATE_PREFIX)
            and all(part not in ("", ".", "..") for part in path.split("/")))


def main():
    changed_paths = sys.stdin.buffer.read()
    if not changed_paths or not changed_paths.endswith(b"\0"):
        print("true")
        return

    paths = changed_paths[:-1].split(b"\0")
    needs_release = any(not path or not is_release_neutral(os.fsdecode(path))
                        for path in paths)
    print("true" if needs_release else "false")


if __name__ == "__main__":
    main()
