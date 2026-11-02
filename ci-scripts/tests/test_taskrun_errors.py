"""Tests for TaskRun-level error attribution in collected artifacts."""

import importlib.util
import json
import sys
import tempfile
import types
import unittest
import unittest.mock
from pathlib import Path

if importlib.util.find_spec("yaml") is None:
    yaml = types.ModuleType("yaml")
    yaml.CSafeLoader = object
    yaml.SafeLoader = object
    sys.modules["yaml"] = yaml

spec = importlib.util.spec_from_file_location(
    "errors", Path(__file__).parent.parent / "errors.py"
)
errors = importlib.util.module_from_spec(spec)
spec.loader.exec_module(errors)


class Matcher:
    """Match a distinctive error token without depending on rules files."""

    def match(self, message, *, quiet=False):
        """Classify a synthetic log or condition."""
        del quiet
        return (
            ("Pull failed", "registry")
            if "PULL_FAILURE" in message
            else ("UNKNOWN", "UNKNOWN")
        )


class TaskrunErrorAttributionTest(unittest.TestCase):
    """Ensure only the failed TaskRun receives its reason."""

    def test_failed_taskrun_reason_uses_its_own_log(self):
        """Classify a failed step log and leave a passing task out."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "namespace" / "0"
            root.mkdir(parents=True)
            (root / "collected-taskrun-failed.json").write_text(
                json.dumps(
                    {
                        "metadata": {"name": "failed"},
                        "status": {
                            "podName": "failed-pod",
                            "conditions": [
                                {
                                    "type": "Succeeded",
                                    "status": "False",
                                    "message": "step failed",
                                }
                            ],
                            "steps": [
                                {
                                    "container": "step-build",
                                    "terminated": {"exitCode": 1},
                                }
                            ],
                        },
                    }
                )
            )
            (root / "pod-failed-pod-step-build.log").write_text("PULL_FAILURE")
            (root / "collected-taskrun-passed.json").write_text(
                json.dumps(
                    {
                        "metadata": {"name": "passed"},
                        "status": {
                            "conditions": [{"type": "Succeeded", "status": "True"}]
                        },
                    }
                )
            )
            analyzer = errors.Analyzer.__new__(errors.Analyzer)
            analyzer.dump_dir = Path(directory)
            analyzer.plr_matcher = Matcher()
            analyzer.tr_matcher = Matcher()
            self.assertEqual(
                analyzer.taskrun_error_reasons(), {"failed": ["Pull failed"]}
            )

    def test_null_metadata_and_status_are_skipped(self):
        """API dumps with null metadata/status must not crash attribution."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "collected-taskrun-null.json").write_text(
                json.dumps({"metadata": None, "status": None})
            )
            analyzer = errors.Analyzer.__new__(errors.Analyzer)
            analyzer.dump_dir = Path(directory)
            analyzer.plr_matcher = Matcher()
            analyzer.tr_matcher = Matcher()
            self.assertEqual(analyzer.taskrun_error_reasons(), {})

    def test_error_matcher_quiet_suppresses_prints(self):
        """Bulk TaskRun matching must not print Unknown/Matched lines."""
        matcher = errors.ErrorMatcher(
            [{"reason": "Pull failed", "regexp": "PULL_FAILURE", "type": "logs"}],
            "logs",
        )
        with unittest.mock.patch("builtins.print") as mocked_print:
            reason, _ = matcher.match("no match here", quiet=True)
            self.assertEqual(reason, "UNKNOWN")
            mocked_print.assert_not_called()
            reason, _ = matcher.match("PULL_FAILURE happened", quiet=True)
            self.assertEqual(reason, "Pull failed")
            mocked_print.assert_not_called()


if __name__ == "__main__":
    unittest.main()
