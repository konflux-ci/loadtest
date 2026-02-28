#!/usr/bin/env python3
"""
Append monitor_pod_container() Jinja lines to cluster_read_config.yaml
from pod-step-names.json. One line per (namespace, pod_id, step).
"""

import argparse
import json
import os


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pod-step-json", required=True, help="pod-step-names.json path")
    ap.add_argument("--yaml-file", required=True, help="cluster_read_config.yaml to append to")
    ap.add_argument("--step-default", type=int, default=15)
    ap.add_argument("--pod-suffix-regex", default="", help="e.g. '' or '-[0-9a-f]+-.*'")
    ap.add_argument("--output", default=None, help="Write modified YAML here (default: overwrite --yaml-file)")
    args = ap.parse_args()

    with open(args.pod_step_json) as f:
        data = json.load(f)

    lines = []
    for entry in data.get("pods", []):
        ns = entry["namespace"]
        pod_id = entry["pod_id"]
        for step in entry["steps"]:
            # Escape single quotes in names for Jinja
            ns_s = ns.replace("'", "''")
            pod_s = pod_id.replace("'", "''")
            step_s = step.replace("'", "''")
            suf = args.pod_suffix_regex.replace("'", "''")
            lines.append(
                "{{ monitor_pod_container('%s', '%s', '%s', %s, '%s') }}"
                % (ns_s, pod_s, step_s, args.step_default, suf)
            )

    with open(args.yaml_file) as f:
        content = f.read()

    suffix = "\n# Dynamic POD/step monitoring (from parsed collected-data)\n"
    suffix += "\n".join(lines)
    suffix += "\n"

    if content.endswith("\n"):
        new_content = content + suffix.lstrip("\n")
    else:
        new_content = content + suffix

    out_path = args.output or args.yaml_file
    with open(out_path, "w") as f:
        f.write(new_content)

    return 0


if __name__ == "__main__":
    exit(main())
