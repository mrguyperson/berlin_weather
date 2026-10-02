"""Offline behavior tests for the PR changed-path classifier."""

import os
from pathlib import Path
import subprocess
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
CLASSIFIER = ROOT / "scripts" / "classify_pr_changes.py"


def classify(*paths):
    changed_paths = b"".join(os.fsencode(path) + b"\0" for path in paths)
    result = subprocess.run(
        [sys.executable, str(CLASSIFIER)],
        input=changed_paths,
        capture_output=True,
        check=True,
    )
    return result.stdout.decode("ascii").strip()


class ChangedPathClassificationTests(unittest.TestCase):
    def test_only_explicit_documentation_and_process_paths_are_lightweight(self):
        cases = (
            ("AGENTS.md",),
            ("README.md", "ROADMAP.md"),
            (".github/ISSUE_TEMPLATE/agent-task.yml",),
            (".github/pull_request_template.md",),
        )
        for paths in cases:
            with self.subTest(paths=paths):
                self.assertEqual(classify(*paths), "false")

    def test_executable_unknown_and_mixed_paths_require_full_validation(self):
        cases = (
            ("R/functions.R",),
            ("index.qmd",),
            ("Dockerfile",),
            ("renv.lock",),
            (".github/workflows/test.yml",),
            ("tests/testthat/test-functions.R",),
            ("scripts/check_doc_paths.py",),
            ("new-file.txt",),
            ("AGENTS.md", "R/functions.R"),
            ("README.md", "index.qmd"),
            (".github/ISSUE_TEMPLATE_BACKUP/task.yml",),
            (".github/ISSUE_TEMPLATE/../workflows/test.yml",),
        )
        for paths in cases:
            with self.subTest(paths=paths):
                self.assertEqual(classify(*paths), "true")

    def test_empty_changed_file_set_requires_full_validation(self):
        self.assertEqual(classify(), "true")


if __name__ == "__main__":
    unittest.main()
