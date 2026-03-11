#!/usr/bin/env python3
"""
Build Task | Step | Memory | CPU data from load-test.json.
For each task/step: show the metric value if present, else "Prometheus didn't return data".
Reads get-pod-step-names.json for the list of (task, step) pairs; falls back to
scanning results.measurements if that file is missing.
Outputs get-task-step-resources.json and get-task-step-resources.html under --artifact-dir.
"""

import argparse
import html
import json
import os
import re
import sys


def get_measurement_value(data):
    """Return a string for display: mean if present, else repr of value or 'Prometheus didn't return data'."""
    if data is None:
        return "Prometheus didn't return data"
    if isinstance(data, dict):
        if "mean" in data and data["mean"] is not None:
            return str(data["mean"])
        if "value" in data:
            return str(data["value"])
        if not data:
            return "Prometheus didn't return data"
        return str(data)
    return str(data)


def collect_from_flat(measurements):
    """Collect task/step/metric from flat keys like 'measurements.tasks[task].step[step].memory'."""
    out = {}
    pattern = re.compile(
        r"^(?:measurements\.)?tasks\[([^\]]+)\]\.step\[([^\]]+)\]\.(memory|cpu)$"
    )
    for key, val in (measurements or {}).items():
        m = pattern.match(key)
        if m:
            task, step, kind = m.groups()
            out.setdefault((task, step), {})[kind] = get_measurement_value(val)
    return out


def collect_from_tasks_bracket_keys(measurements):
    """Collect from keys like 'tasks[taskname]' with value { 'step[stepname]': { memory: {...}, cpu: {...} } }."""
    out = {}
    task_prefix = "tasks["
    task_suffix = "]"
    for key, step_dict in (measurements or {}).items():
        if (
            not isinstance(key, str)
            or not key.startswith(task_prefix)
            or task_suffix not in key
        ):
            continue
        task_name = key[len(task_prefix) : key.index(task_suffix)]
        if not isinstance(step_dict, dict):
            continue
        for step_key, metric_dict in step_dict.items():
            if not isinstance(metric_dict, dict):
                continue
            step_name = step_key
            if step_key.startswith("step[") and step_key.endswith("]"):
                step_name = step_key[5:-1]
            mem = metric_dict.get("memory")
            cpu = metric_dict.get("cpu")
            out[(task_name, step_name)] = {
                "memory": get_measurement_value(mem)
                if mem is not None
                else "Prometheus didn't return data",
                "cpu": get_measurement_value(cpu)
                if cpu is not None
                else "Prometheus didn't return data",
            }
    return out


def collect_from_nested(measurements):
    """Collect from nested structure: measurements.tasks[task][step_key].memory/.cpu."""
    out = {}
    tasks = measurements.get("tasks") if isinstance(measurements, dict) else None
    if not isinstance(tasks, dict):
        return out
    for task_name, step_dict in tasks.items():
        if not isinstance(step_dict, dict):
            continue
        for step_key, metric_dict in step_dict.items():
            if not isinstance(metric_dict, dict):
                continue
            step_name = step_key
            if step_key.startswith("step[") and step_key.endswith("]"):
                step_name = step_key[5:-1]
            mem = metric_dict.get("memory")
            cpu = metric_dict.get("cpu")
            out[(task_name, step_name)] = {
                "memory": get_measurement_value(mem)
                if mem is not None
                else "Prometheus didn't return data",
                "cpu": get_measurement_value(cpu)
                if cpu is not None
                else "Prometheus didn't return data",
            }
    return out


def main():
    ap = argparse.ArgumentParser(
        description="Build task/step Memory and CPU from load-test.json; output JSON and HTML."
    )
    ap.add_argument(
        "--load-test-json", default="load-test.json", help="Path to load-test.json"
    )
    ap.add_argument(
        "--pod-step-json",
        default="get-pod-step-names.json",
        help="Path to get-pod-step-names.json (optional)",
    )
    ap.add_argument(
        "--artifact-dir",
        required=True,
        help="Directory to read inputs from and write get-task-step-resources.json/html to",
    )
    args = ap.parse_args()

    base = args.artifact_dir
    load_test_path = os.path.join(base, args.load_test_json)
    pod_step_path = os.path.join(base, args.pod_step_json)

    if not os.path.isfile(load_test_path):
        print("Error: load-test.json not found at", load_test_path, file=sys.stderr)
        return 1

    with open(load_test_path) as f:
        data = json.load(f)

    measurements_root = data.get("measurements") or {}
    measurements_results = (data.get("results") or {}).get("measurements") or {}

    collected = {}
    for m in (measurements_root, measurements_results):
        if not isinstance(m, dict):
            continue
        collected.update(collect_from_flat(m))
        collected.update(collect_from_tasks_bracket_keys(m))
        collected.update(collect_from_nested(m))

    expected = []
    if os.path.isfile(pod_step_path):
        try:
            with open(pod_step_path) as f:
                pod_data = json.load(f)
            for entry in pod_data.get("pods", []):
                task_name = entry.get("task_name") or entry.get("pod_id", "")
                for step in entry.get("steps", []):
                    expected.append((task_name, step))
        except Exception:
            pass

    if expected:
        rows = []
        seen = set()
        for task, step in expected:
            key = (task, step)
            seen.add(key)
            row = collected.get(key, {})
            rows.append(
                (
                    task,
                    step,
                    row.get("memory", "Prometheus didn't return data"),
                    row.get("cpu", "Prometheus didn't return data"),
                )
            )
        for key in sorted(collected):
            if key not in seen:
                task, step = key
                row = collected[key]
                rows.append(
                    (
                        task,
                        step,
                        row.get("memory", "Prometheus didn't return data"),
                        row.get("cpu", "Prometheus didn't return data"),
                    )
                )
    else:
        rows = []
        for (task, step), row in sorted(collected.items()):
            rows.append(
                (
                    task,
                    step,
                    row.get("memory", "Prometheus didn't return data"),
                    row.get("cpu", "Prometheus didn't return data"),
                )
            )

    if not rows:
        rows = [
            (
                "(no task/step metrics found)",
                "",
                "Prometheus didn't return data",
                "Prometheus didn't return data",
            )
        ]

    # Build list of dicts for JSON
    table = [
        {"task": task, "step": step, "memory": mem, "cpu": cpu}
        for task, step, mem, cpu in rows
    ]

    json_path = os.path.join(base, "get-task-step-resources.json")
    with open(json_path, "w") as f:
        json.dump({"rows": table}, f, indent=2)

    html_path = os.path.join(base, "get-task-step-resources.html")
    # Merge consecutive same-task rows: Task column uses rowspan so each task name appears once.
    html_row_parts = []
    i = 0
    while i < len(rows):
        task, step, mem, cpu = rows[i]
        # Count consecutive rows with same task
        j = i + 1
        while j < len(rows) and rows[j][0] == task:
            j += 1
        rowspan = j - i
        # First row of this task: include Task cell with rowspan
        html_row_parts.append(
            f'    <tr><td rowspan="{rowspan}">{html.escape(task)}</td>'
            f"<td>{html.escape(step)}</td><td>{html.escape(mem)}</td><td>{html.escape(cpu)}</td></tr>\n"
        )
        # Remaining rows for this task: no Task cell
        for k in range(i + 1, j):
            _, step, mem, cpu = rows[k]
            html_row_parts.append(
                f"    <tr><td>{html.escape(step)}</td><td>{html.escape(mem)}</td><td>{html.escape(cpu)}</td></tr>\n"
            )
        i = j
    html_rows = "".join(html_row_parts)
    html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Task / Step resources (Memory, CPU)</title>
  <style>
    table {{ border-collapse: collapse; }}
    th, td {{ border: 1px solid #333; padding: 6px 10px; text-align: left; }}
    th {{ background: #eee; }}
    td[rowspan] {{ vertical-align: top; }}
  </style>
</head>
<body>
  <h1>Task / Step resources (Memory, CPU)</h1>
  <table>
    <thead>
      <tr><th>Task</th><th>Step</th><th>Memory</th><th>CPU</th></tr>
    </thead>
    <tbody>
{html_rows}    </tbody>
  </table>
</body>
</html>
"""
    with open(html_path, "w") as f:
        f.write(html_content)

    return 0


if __name__ == "__main__":
    sys.exit(main())
