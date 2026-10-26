import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


spec = importlib.util.spec_from_file_location(
    "evaluate", Path(__file__).with_name("evaluate.py")
)
evaluate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evaluate)


class TaskLocationsTest(unittest.TestCase):
    def test_taskrun_pod_and_vm_are_correlated(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "namespace" / "0"
            root.mkdir(parents=True)
            (root / "collected-taskrun-build.json").write_text(
                json.dumps(
                    {
                        "metadata": {
                            "name": "build",
                            "creationTimestamp": "2026-03-26T15:00:00Z",
                            "labels": {
                                "tekton.dev/pipelineRun": "pipeline",
                                "tekton.dev/task": "build-images",
                                "pipelines.appstudio.openshift.io/type": "build",
                                "build.appstudio.redhat.com/target-platform": "linux-arm64",
                            },
                        },
                        "status": {
                            "podName": "build-pod",
                            "completionTime": "2026-03-26T15:02:00Z",
                            "conditions": [{"type": "Succeeded", "status": "True"}],
                        },
                    }
                )
            )
            (root / "collected-pod-build-pod.json").write_text(
                json.dumps(
                    {
                        "metadata": {"name": "build-pod"},
                        "spec": {"nodeName": "worker-1"},
                    }
                )
            )
            (root / "pod-build-pod-step-build.log").write_text(
                "Warning: Permanently added '10.130.72.59' (ED25519) to the list of known hosts.\n"
            )

            self.assertEqual(
                evaluate.task_locations(directory)["build"],
                {
                    "pipelinerun": "pipeline",
                    "task": "build-images",
                    "pipeline_type": "build",
                    "platform": "linux-arm64",
                    "pod": "build-pod",
                    "node": "worker-1",
                    "vm": "10.130.72.59",
                    "duration": 120.0,
                    "succeeded": True,
                },
            )

    def test_missing_pod_and_ambiguous_vm_are_not_attributed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "collected-taskrun-build.json").write_text(
                json.dumps(
                    {
                        "metadata": {"name": "build"},
                        "status": {"podName": "build-pod"},
                    }
                )
            )
            (root / "pod-build-pod-step-build.log").write_text(
                "Permanently added '10.0.0.1' (ED25519) to the list of known hosts\n"
                "Permanently added '10.0.0.2' (ED25519) to the list of known hosts\n"
            )
            location = evaluate.task_locations(directory)["build"]
            self.assertIsNone(location["node"])
            self.assertIsNone(location["vm"])

    def test_annotation_is_preferred_to_log(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "collected-taskrun-build.json").write_text(
                json.dumps(
                    {
                        "metadata": {
                            "name": "build",
                            "annotations": {
                                "build.appstudio.redhat.com/cloud-address": "10.207.1.250"
                            },
                        },
                        "status": {"podName": "build-pod"},
                    }
                )
            )
            (root / "pod-build-pod-step-build.log").write_text(
                "Permanently added '10.0.0.1' (ED25519) to the list of known hosts\n"
            )
            self.assertEqual(
                evaluate.task_locations(directory)["build"]["vm"], "10.207.1.250"
            )


if __name__ == "__main__":
    unittest.main()
