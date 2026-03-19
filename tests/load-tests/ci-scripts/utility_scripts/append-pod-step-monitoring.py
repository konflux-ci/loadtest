#!/usr/bin/env python3
"""
Emit full cluster_read_config.yaml (base + dynamic lines) to stdout
from get-pod-step-names.json. Base file is ci-scripts/stage/cluster_read_config.yaml.
"""

import argparse
import json
import os


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--pod-step-json", required=True, help="get-pod-step-names.json path"
    )
    ap.add_argument("--step-default", type=int, default=15)
    ap.add_argument("--pod-suffix-regex", default="", help="e.g. '' or '-[0-9a-f]+-.*'")
    args = ap.parse_args()

    with open(args.pod_step_json) as f:
        data = json.load(f)

    input_yaml = os.path.abspath(
        os.path.join(
            os.path.dirname(__file__), "..", "stage", "cluster_read_config.yaml"
        )
    )

    lines = []
    for entry in data.get("pods", []):
        ns = entry["namespace"]
        pod_id = entry["pod_id"]
        task_name = entry.get("task_name", pod_id)
        for step in entry["steps"]:
            lines.append(
                "{{ monitor_task_step('%s', '%s', '%s', '%s', %s, '%s') }}"
                % (
                    ns,
                    pod_id,
                    task_name,
                    step,
                    args.step_default,
                    args.pod_suffix_regex,
                )
            )

    with open(input_yaml) as f:
        content = f.read()

    suffix = "\n# Dynamic task/step monitoring (from parsed collected-data; stored under task name)\n"
    suffix += "\n".join(lines)
    suffix += "\n"

    print(content + suffix, end="")
    return 0


if __name__ == "__main__":
    exit(main())
