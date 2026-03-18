#!/usr/bin/env python3
import argparse
import html
import json
import os


def format_metric(metric, divisor=1, precision=None):
    if isinstance(metric, dict) and "mean" in metric and metric["mean"] is not None:
        val = float(metric["mean"]) / divisor
        if precision is not None:
            return f"{val:.{precision}f}"
        return str(val)
    return "Prometheus didn't return data"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--load-test-json", default="load-test.json")
    parser.add_argument("--pod-step-json", default="get-pod-step-names.json")
    parser.add_argument("--output-html-file", default="get-task-step-resources.html")
    args = parser.parse_args()

    pod_path = args.pod_step_json
    pod_data = json.load(open(pod_path)) if os.path.exists(pod_path) else {}

    lt_path = args.load_test_json
    lt_data = json.load(open(lt_path)) if os.path.exists(lt_path) else {}
    load_test = lt_data.get("measurements", {})

    taskruns = load_test.get("taskruns", {})
    steps = load_test.get("steps", {})

    def get_all_items():
        for pod in pod_data.get("pods", []):
            task = pod.get("task_name")
            if task:
                for step in pod.get("steps", []):
                    yield task, step
                if not pod.get("steps"):
                    yield task, None
        for task in taskruns.keys():
            yield task, None
        for step_key in steps.keys():
            if "/" in step_key:
                yield tuple(step_key.rsplit("/", 1))
            else:
                yield step_key, None

    # Combine all sources into a single task -> steps mapping in one loop
    tasks_map = {}
    for task, step in get_all_items():
        tasks_map.setdefault(task, set())
        if step:
            tasks_map[task].add(step)

    html_rows = []
    if not tasks_map:
        html_rows.append('    <tr><td colspan="4">No tasks found</td></tr>\n')
    else:
        mem_div = 1024 * 1024 * 1024
        for task_name in sorted(tasks_map.keys()):
            step_names = sorted(tasks_map[task_name])

            t_data = taskruns.get(task_name, {})
            t_mem = format_metric(t_data.get("memory"), divisor=mem_div, precision=2)
            t_cpu = format_metric(t_data.get("cpu"), precision=2)

            rowspan = len(step_names) + 1
            e_task = html.escape(task_name)
            e_mem = html.escape(t_mem)
            e_cpu = html.escape(t_cpu)
            html_rows.append(
                f'    <tr><td rowspan="{rowspan}">{e_task}</td>\n'
                f"        <td>(Task Total)</td><td>{e_mem}</td><td>{e_cpu}</td></tr>\n"
            )

            for step_name in step_names:
                s_key = f"{task_name}/{step_name}"
                s_data = steps.get(s_key, {})
                s_mem = format_metric(
                    s_data.get("memory"), divisor=mem_div, precision=2
                )
                s_cpu = format_metric(s_data.get("cpu"), precision=2)
                e_step = html.escape(step_name)
                e_smem = html.escape(s_mem)
                e_scpu = html.escape(s_cpu)
                html_rows.append(
                    f"    <tr><td>{e_step}</td><td>{e_smem}</td><td>{e_scpu}</td></tr>\n"
                )

    html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Task / Step resources (Memory GB, CPU cores)</title>
  <style>
    table {{ border-collapse: collapse; }}
    th, td {{ border: 1px solid #333; padding: 6px 10px; text-align: left; }}
    th {{ background: #eee; }}
    td[rowspan] {{ vertical-align: top; }}
  </style>
</head>
<body>
  <h1>Task / Step resources (Memory GB, CPU cores)</h1>
  <table>
    <thead>
      <tr><th>Task</th><th>Step</th><th>Memory [GB]</th><th>CPU [cores]</th></tr>
    </thead>
    <tbody>
{"".join(html_rows)}    </tbody>
  </table>
</body>
</html>
"""
    with open(args.output_html_file, "w") as f:
        f.write(html_content)


if __name__ == "__main__":
    main()
