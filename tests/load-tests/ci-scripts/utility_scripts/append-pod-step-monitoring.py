#!/usr/bin/env python3
"""
Generate monitor_task() and monitor_task_step() macro calls in Jinja2 for
cluster_read_config.yaml from get-pod-step-names.json.
"""

import argparse
import json


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--pod-step-json",
        required=True,
        help="get-pod-step-names.json path",
    )
    ap.add_argument(
        "--step-default",
        type=int,
        default=15,
    )
    ap.add_argument(
        "--pod-suffix-regex",
        default="",
        help="e.g. '' or '-[0-9a-f]+-.*'",
    )
    args = ap.parse_args()

    with open(args.pod_step_json) as f:
        data = json.load(f)

    print(
        "\n# Dynamic task/step monitoring from parsed collected-data; stored under task name)\n"
    )

    for entry in data.get("pods", []):
        ns = entry["namespace"]
        pod_id = entry["pod_id"]
        task_name = entry["task_name"]

        print(
            f"{{ monitor_task('{ns}', '{pod_id}', '{task_name}', {args.step_default}, '{args.pod_suffix_regex}') }}"
        )

        for step in entry["steps"]:
            print(
                f"{{ monitor_task_step('{ns}', '{pod_id}', 'step-{step}', '{task_name}/{step}', {args.step_default}, '{args.pod_suffix_regex}') }}"
            )

    return 0


if __name__ == "__main__":
    exit(main())
