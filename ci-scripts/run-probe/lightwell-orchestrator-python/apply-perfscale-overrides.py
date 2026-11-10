#!/usr/bin/env python3
"""Apply KONFLUX-16318 perfscale retarget overlays to a cloned orchestrator tree.

Upstream lightwell-konflux-orchestrator defaults to lightwell-python-tenant /
packages.redhat.com / lightwell-builds-git-auth. The Option B probe on
kflux-lw-p01 needs konflux-perfscale-3-tenant, the jhutar ntplib source, flat
ImageRepository URL, probe git-auth secret, empty wheel server, and
skip_release on REMEDIATED.

These overlays stay in loadtest until upstream grows first-class env overrides.
Do not push equivalent hardcodes to the orchestrator main branch.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

NAMESPACE = "konflux-perfscale-3-tenant"
IMAGE_REPO_BASE = (
    "quay.io/redhat-user-workloads/konflux-perfscale-3-tenant/remediated-build"
)
GIT_AUTH_SECRET = "probe-build-configs-git-auth"
BUILDS_REPO_URL = "https://gitlab.cee.redhat.com/jhutar/lw-pypi.org-ntplib-1"

PIPELINERUN_OVERRIDE = '''\
    # Perfscale probe overlay (KONFLUX-16318): flat IR URL + jhutar source repo.
    if getattr(config, "LIGHTWELL_BUILDS_REPO_URL_OVERRIDE", None):
        image = f"{image_repo_base}:{package}-{version}"
        repo_url = config.LIGHTWELL_BUILDS_REPO_URL_OVERRIDE
    else:
        image = f"{image_repo_base}/{application}/{component}:{package}-{version}"
        repo_url = f"{repo_base}/pypi.org-{package}"
'''


def _replace_assignment(text: str, name: str, value: str) -> str:
    pattern = rf"^({re.escape(name)}\s*=\s*).*$"
    new_text, count = re.subn(pattern, rf"\1{value}", text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"failed to rewrite assignment {name}: matches={count}")
    return new_text


def _replace_wheel_server(text: str) -> str:
    pattern = re.compile(
        r"^WHEEL_SERVER_URL\s*=\s*os\.environ\.get\(\s*\"WHEEL_SERVER_URL\".*?\)\s*$",
        flags=re.MULTILINE | re.DOTALL,
    )
    new_text, count = pattern.subn(
        'WHEEL_SERVER_URL = os.environ.get("WHEEL_SERVER_URL", "")',
        text,
        count=1,
    )
    if count != 1:
        raise SystemExit(f"failed to rewrite WHEEL_SERVER_URL: matches={count}")
    return new_text


def _ensure_skip_release_remediated(text: str) -> str:
    match = re.search(r'("REMEDIATED"\s*:\s*\{)([^{}]*)(\})', text, flags=re.DOTALL)
    if not match:
        raise SystemExit("REMEDIATED target block not found")
    body = match.group(2)
    if "skip_release" in body:
        return text
    trimmed = body.rstrip()
    if not trimmed.endswith(","):
        trimmed += ","
    new_body = trimmed + '\n        "skip_release": True,\n    '
    return text[: match.start(2)] + new_body + text[match.end(2) :]


def patch_config(path: Path) -> None:
    text = path.read_text()
    text = _replace_assignment(text, "NAMESPACE", f'"{NAMESPACE}"')
    text = _replace_assignment(text, "IMAGE_REPO_BASE", f'"{IMAGE_REPO_BASE}"')
    text = _replace_assignment(text, "GIT_AUTH_SECRET", f'"{GIT_AUTH_SECRET}"')
    text = _replace_wheel_server(text)
    text = _ensure_skip_release_remediated(text)

    if "LIGHTWELL_BUILDS_REPO_URL_OVERRIDE" not in text:
        insert = (
            "\n# Perfscale probe overlay (KONFLUX-16318).\n"
            f'LIGHTWELL_BUILDS_REPO_URL_OVERRIDE = "{BUILDS_REPO_URL}"\n'
        )
        needle = f'IMAGE_REPO_BASE = "{IMAGE_REPO_BASE}"'
        if needle not in text:
            raise SystemExit("IMAGE_REPO_BASE assignment not found after rewrite")
        text = text.replace(needle, needle + insert, 1)

    path.write_text(text)
    print(f"patched {path}")


def patch_pipelinerun(path: Path) -> None:
    text = path.read_text()
    if "LIGHTWELL_BUILDS_REPO_URL_OVERRIDE" in text:
        print(f"already overlaid {path}")
        return

    old_image = '    image = f"{image_repo_base}/{application}/{component}:{package}-{version}"'
    if old_image not in text:
        raise SystemExit("pipelinerun.py image assignment not found for overlay")
    text = text.replace(old_image, PIPELINERUN_OVERRIDE.rstrip(), 1)

    old_repo = '{"name": "LIGHTWELL_BUILDS_REPO_URL", "value": f"{repo_base}/pypi.org-{package}"}'
    new_repo = '{"name": "LIGHTWELL_BUILDS_REPO_URL", "value": repo_url}'
    if new_repo in text or '"value": resolve_repo_url(package, repo_base, repo_url)' in text:
        path.write_text(text)
        print(f"patched {path}")
        return
    if old_repo not in text:
        raise SystemExit("pipelinerun.py LIGHTWELL_BUILDS_REPO_URL param not found")
    text = text.replace(old_repo, new_repo, 1)

    path.write_text(text)
    print(f"patched {path}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "orchestrator_dir",
        type=Path,
        help="Path to cloned lightwell-konflux-orchestrator checkout",
    )
    args = parser.parse_args()
    root = args.orchestrator_dir.resolve()
    config_path = root / "src/import_orchestrator/ecosystems/python/config.py"
    pipelinerun_path = root / "src/import_orchestrator/ecosystems/python/pipelinerun.py"
    if not config_path.is_file() or not pipelinerun_path.is_file():
        print(f"ERROR: orchestrator sources not found under {root}", file=sys.stderr)
        return 2
    patch_config(config_path)
    patch_pipelinerun(pipelinerun_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
