#!/usr/bin/env python3
"""
Append monitor_task_step() Jinja lines to cluster_read_config.yaml
from get-pod-step-names.json. One line per (namespace, pod_id, task_name, step).
Metrics are stored under task name (stable across runs); Prometheus query uses step-<step> for container.
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
    ap.add_argument("--output", required=True, help="Write modified YAML here")
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

    new_content = content + suffix
    with open(args.output, "w") as f:
        f.write(new_content)

    return 0


if __name__ == "__main__":
    exit(main())
