#!/usr/bin/env python3
"""Fail when project documentation names a repository path that does not exist."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
DOCUMENTS = ("README.md", "AGENTS.md", "ROADMAP.md")
PATH_PREFIXES = (
    ".devcontainer/",
    ".github/",
    "R/",
    "renv/",
    "scripts/",
    "tests/",
    "_targets/",
)
ROOT_PATHS = {
    ".Rprofile",
    "AGENTS.md",
    "DESCRIPTION",
    "Dockerfile",
    "README.md",
    "ROADMAP.md",
    "_quarto.yml",
    "_targets.R",
    "index.qmd",
    "renv.lock",
}
INLINE_CODE = re.compile(r"(?<!`)`([^`\n]+)`(?!`)")
WILDCARDS = set("*?[]{}")


def documented_paths(line: str):
    for match in INLINE_CODE.finditer(line):
        candidate = match.group(1)
        if any(character in candidate for character in WILDCARDS):
            continue
        if candidate in ROOT_PATHS or candidate.startswith(PATH_PREFIXES):
            yield candidate


def main() -> int:
    stale = []
    for document in DOCUMENTS:
        path = ROOT / document
        for line_number, line in enumerate(path.read_text().splitlines(), start=1):
            for candidate in documented_paths(line):
                if not (ROOT / candidate.rstrip("/")).exists():
                    stale.append((document, line_number, candidate))

    if stale:
        for document, line_number, candidate in stale:
            print(
                f"{document}:{line_number}: stale repository path: {candidate}",
                file=sys.stderr,
            )
        return 1

    print("Documented repository paths are current.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
