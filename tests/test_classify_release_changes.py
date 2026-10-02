"""Offline tests for the production release-change policy."""

import os
from pathlib import Path
import subprocess
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
CLASSIFIER = ROOT / "scripts" / "classify_release_changes.py"


def requires_release(*paths, raw=None):
    changed_paths = raw if raw is not None else b"".join(
        os.fsencode(path) + b"\0" for path in paths
    )
    result = subprocess.run(
        [sys.executable, str(CLASSIFIER)],
        input=changed_paths,
        capture_output=True,
        check=True,
    )
    return result.stdout.decode("ascii").strip()


class ReleaseChangeClassificationTests(unittest.TestCase):
    def test_explicit_documentation_paths_are_release_neutral(self):
        cases = (
            ("AGENTS.md",),
            ("README.md", "ROADMAP.md"),
            (".github/pull_request_template.md",),
            (".github/ISSUE_TEMPLATE/agent-task.yml",),
        )
        for paths in cases:
            with self.subTest(paths=paths):
                self.assertEqual(requires_release(*paths), "false")

    def test_executable_unknown_and_mixed_paths_require_release(self):
        cases = (
            ("R/functions.R",),
            ("_targets.R",),
            ("index.qmd",),
            ("Dockerfile",),
            ("renv.lock",),
            (".github/workflows/build-image.yml",),
            (".github/workflows/publish.yml",),
            ("scripts/classify_release_changes.py",),
            ("tests/test_classify_release_changes.py",),
            ("new-file.txt",),
            ("README.md", "R/functions.R"),
            ("AGENTS.md", "index.qmd"),
            (".github/ISSUE_TEMPLATE_BACKUP/task.yml",),
            (".github/ISSUE_TEMPLATE/../workflows/publish.yml",),
        )
        for paths in cases:
            with self.subTest(paths=paths):
                self.assertEqual(requires_release(*paths), "true")

    def test_empty_and_malformed_input_requires_release(self):
        self.assertEqual(requires_release(), "true")
        self.assertEqual(requires_release(raw=b"AGENTS.md"), "true")
        self.assertEqual(requires_release(raw=b"AGENTS.md\0\0"), "true")


if __name__ == "__main__":
    unittest.main()
