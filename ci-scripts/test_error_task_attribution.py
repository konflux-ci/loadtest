"""Tests for task-level error attribution in collected artifacts."""

import importlib.util
import json
import sys
import tempfile
import types
import unittest
from pathlib import Path


if importlib.util.find_spec("yaml") is None:
    yaml = types.ModuleType("yaml")
    yaml.CSafeLoader = object
    yaml.SafeLoader = object
    sys.modules["yaml"] = yaml

spec = importlib.util.spec_from_file_location(
    "errors", Path(__file__).with_name("errors.py")
)
errors = importlib.util.module_from_spec(spec)
spec.loader.exec_module(errors)


class Matcher:
    """Match a distinctive error token without depending on rules files."""

    def match(self, message):
        """Classify a synthetic log or condition."""
        return (
            ("Pull failed", "registry")
            if "PULL_FAILURE" in message
            else ("UNKNOWN", "UNKNOWN")
        )


class TaskErrorAttributionTest(unittest.TestCase):
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
            self.assertEqual(analyzer.task_error_reasons(), {"failed": ["Pull failed"]})


if __name__ == "__main__":
    unittest.main()
