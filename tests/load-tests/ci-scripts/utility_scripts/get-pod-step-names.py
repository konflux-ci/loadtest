#!/usr/bin/env python3
"""
Parse collected-data directory for POD-specific log files and extract
POD IDs (Tekton Task pods) and step names (containers) for each POD.

Filename pattern: pod-<POD_ID>-pod-step-<STEP_NAME>.log
We only consider -pod-step-* files (not -pod-prepare or -pod-place-scripts).
Output: JSON and human-readable dump for logs.
"""

import argparse
import json
import os
import sys
from collections import defaultdict


def parse_pod_step_from_basename(basename):
    """
    From a basename like 'pod-stgrh01css-app-kmwaz-comp-0b43f0e664f6c4165ba11655d5ff16c5d-pod-step-rpms-signature-scan'
    return (pod_id, step_name) or (None, None) if not a step log.
    """
    if not basename.endswith(".log"):
        basename = basename + ".log"
    base = basename[:-4]  # strip .log
    if "-pod-step-" not in base:
        return None, None
    prefix = "pod-"
    if not base.startswith(prefix):
        return None, None
    rest = base[len(prefix) :]
    parts = rest.split("-pod-step-", 1)
    if len(parts) != 2:
        return None, None
    pod_id, step_name = parts[0], parts[1]
    return pod_id, step_name


def collect_pods_and_steps(data_dir):
    """
    Walk ARTIFACT_DIR/collected-data/<namespace>/<run_id>/ and collect
    (namespace, pod_id) -> list of step names (from pod-*-pod-step-*.log).
    """
    collected_data = os.path.join(data_dir, "collected-data")
    if not os.path.isdir(collected_data):
        return []

    # (namespace, pod_id) -> set of step names
    by_pod = defaultdict(set)
    by_pod_list = defaultdict(list)  # keep order

    for namespace in sorted(os.listdir(collected_data)):
        ns_path = os.path.join(collected_data, namespace)
        if not os.path.isdir(ns_path):
            continue
        for run_id in sorted(os.listdir(ns_path)):
            run_path = os.path.join(ns_path, run_id)
            if not os.path.isdir(run_path):
                continue
            for f in os.listdir(run_path):
                if not f.endswith(".log") or not f.startswith("pod-"):
                    continue
                pod_id, step_name = parse_pod_step_from_basename(f)
                if pod_id is None:
                    continue
                key = (namespace, pod_id)
                if step_name not in by_pod[key]:
                    by_pod[key].add(step_name)
                    by_pod_list[key].append(step_name)

    # Build list of dicts for JSON: [ {"namespace": ns, "pod_id": pid, "steps": [...] }, ... ]
    result = []
    for (namespace, pod_id) in sorted(by_pod_list.keys()):
        result.append({
            "namespace": namespace,
            "pod_id": pod_id,
            "steps": by_pod_list[(namespace, pod_id)],
        })
    return result


def main():
    ap = argparse.ArgumentParser(description="Parse POD/step names from collected-data log filenames")
    ap.add_argument("--data-dir", required=True, help="ARTIFACT_DIR (contains collected-data/)")
    ap.add_argument("--dump-json", required=True, help="Write JSON output here")
    ap.add_argument("--dump-log", default=None, help="Optional: write human-readable dump here (else stdout)")
    args = ap.parse_args()

    data = collect_pods_and_steps(args.data_dir)

    with open(args.dump_json, "w") as f:
        json.dump({"pods": data}, f, indent=2)

    lines = []
    lines.append("POD and step names (namespace, pod_id, steps):")
    lines.append("-" * 60)
    for entry in data:
        lines.append("  namespace: %s" % entry["namespace"])
        lines.append("  pod_id:    %s" % entry["pod_id"])
        lines.append("  steps:     %s" % ", ".join(entry["steps"]))
        lines.append("")
    lines.append("Total: %d PODs" % len(data))
    text = "\n".join(lines)

    if args.dump_log:
        with open(args.dump_log, "w") as f:
            f.write(text)
    else:
        print(text, end="")

    return 0


if __name__ == "__main__":
    sys.exit(main())
