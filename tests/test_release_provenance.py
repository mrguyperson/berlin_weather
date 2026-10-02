"""Offline tests for classifying the exact main-push range from build provenance."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
RESOLVER = ROOT / "scripts" / "classify_release_provenance.py"


class ReleaseProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name)
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        (self.repo / "README.md").write_text("initial\n")
        (self.repo / "R").mkdir()
        (self.repo / "R/functions.R").write_text("initial\n")
        self.initial = self.commit("initial")

    def commit(self, label):
        subprocess.run(["git", "add", "."], cwd=self.repo, check=True)
        subprocess.run([
            "git", "-c", "user.name=Test", "-c", "user.email=test@example.com",
            "commit", "-qm", label,
        ], cwd=self.repo, check=True)
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=self.repo, text=True
        ).strip()

    def change(self, name, label):
        path = self.repo / name
        path.write_text(label + "\n")
        return self.commit(label)

    def classify(self, previous, source, *, recorded_source=None,
                 run_head=None, event="push", raw=None, missing=False):
        provenance = self.repo / "release-provenance.json"
        if missing:
            provenance.unlink(missing_ok=True)
        elif raw is not None:
            provenance.write_text(raw)
        else:
            provenance.write_text(json.dumps({
                "source_sha": recorded_source or source,
                "previous_sha": previous,
                "event": event,
            }))
        result = subprocess.run([
            sys.executable, str(RESOLVER),
            "--provenance", str(provenance),
            "--source-sha", source,
            "--run-head-sha", run_head or source,
            "--trigger-event", "push",
        ], cwd=self.repo, capture_output=True, check=True)
        return result.stdout.decode("ascii").strip()

    def test_single_release_neutral_commit(self):
        source = self.change("README.md", "docs")
        self.assertEqual(self.classify(self.initial, source), "false")

    def test_multiple_release_neutral_commits(self):
        self.change("README.md", "docs one")
        (self.repo / "ROADMAP.md").write_text("docs two\n")
        source = self.commit("docs two")
        self.assertEqual(self.classify(self.initial, source), "false")

    def test_code_then_docs_must_not_use_only_the_last_commit(self):
        code = self.change("R/functions.R", "code")
        source = self.change("README.md", "docs")
        self.assertEqual(self.classify(self.initial, source), "true")
        self.assertEqual(self.classify(code, source), "false")

    def test_docs_then_code_requires_release(self):
        self.change("README.md", "docs")
        source = self.change("R/functions.R", "code")
        self.assertEqual(self.classify(self.initial, source), "true")

    def test_bad_or_missing_provenance_requires_release(self):
        source = self.change("README.md", "docs")
        cases = (
            {"missing": True},
            {"raw": "not json"},
            {"raw": "{}"},
            {"previous": "not-a-sha"},
            {"recorded_source": self.initial},
            {"run_head": self.initial},
            {"event": "workflow_dispatch"},
        )
        for case in cases:
            with self.subTest(case=case):
                arguments = {"previous": self.initial, "source": source} | case
                self.assertEqual(self.classify(**arguments), "true")

        unrelated = "f" * 40
        self.assertEqual(self.classify(unrelated, source), "true")

        subprocess.run(["git", "checkout", "-q", "--detach", self.initial],
                       cwd=self.repo, check=True)
        sibling = self.change("README.md", "other branch")
        self.assertEqual(self.classify(sibling, source), "true")


if __name__ == "__main__":
    unittest.main()
