#!/usr/bin/env python3
"""Export Terraform state inventory for the local TP IaC student VM."""

from __future__ import annotations

import json
import os
import socket
import tempfile
from pathlib import Path
from typing import Any


OUTPUT = Path("/var/lib/node_exporter/textfile_collector/tpiac_tfstate.prom")
STUDENT_VM = socket.gethostname()
SKIP_DIRS = {"/dev", "/proc", "/run", "/sys", "/var/lib/docker", "/var/lib/containerd"}


def escape(value: Any) -> str:
    text = str(value if value is not None else "")
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def label(name: str, value: Any) -> str:
    return f'{name}="{escape(value)}"'


def state_files() -> list[Path]:
    found: list[Path] = []
    for root, dirs, files in os.walk("/", topdown=True, onerror=lambda _error: None):
        dirs[:] = [d for d in dirs if str(Path(root, d)) not in SKIP_DIRS]
        if "terraform.tfstate" not in files:
            continue
        path = Path(root, "terraform.tfstate")
        try:
            if path.stat().st_size > 200:
                found.append(path)
        except OSError:
            continue
    return sorted(found)


def attributes(instance: dict[str, Any]) -> dict[str, Any]:
    return instance.get("attributes") or {}


def main() -> int:
    lines = [
        "# HELP tpiac_terraform_state_files Number of non-empty Terraform state files on the student VM.",
        "# TYPE tpiac_terraform_state_files gauge",
        "# HELP tpiac_terraform_state_file Terraform state file discovered on the student VM.",
        "# TYPE tpiac_terraform_state_file gauge",
        "# HELP tpiac_terraform_managed_instance EC2 instance recorded in a Terraform state file.",
        "# TYPE tpiac_terraform_managed_instance gauge",
        "# HELP tpiac_terraform_state_scan_success Whether the state inventory scan completed.",
        "# TYPE tpiac_terraform_state_scan_success gauge",
        "# HELP tpiac_terraform_state_parse_errors Number of state files that could not be parsed.",
        "# TYPE tpiac_terraform_state_parse_errors gauge",
    ]
    states = state_files()
    errors = 0
    lines.append(f"tpiac_terraform_state_files{{{label('student_vm', STUDENT_VM)}}} {len(states)}")
    for path in states:
        try:
            relative = path.relative_to(Path.home().parent)
        except ValueError:
            relative = path.relative_to("/")
        state_path = f"/{relative.as_posix()}"
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            errors += 1
            continue
        lines.append(
            "tpiac_terraform_state_file{"
            + ",".join((label("student_vm", STUDENT_VM), label("state_path", state_path)))
            + f"}} {path.stat().st_size}"
        )
        for resource in data.get("resources", []):
            if resource.get("mode") != "managed" or resource.get("type") != "aws_instance":
                continue
            address = ".".join(
                part for part in (resource.get("module"), resource.get("type"), resource.get("name")) if part
            )
            for instance in resource.get("instances", []):
                attrs = attributes(instance)
                tags = attrs.get("tags") or {}
                values = (
                    label("student_vm", STUDENT_VM),
                    label("state_path", state_path),
                    label("resource_address", address),
                    label("name", tags.get("Name", "unknown")),
                    label("owner_tag", tags.get("filter", "unknown")),
                    label("region", attrs.get("availability_zone", "")[:-1]),
                    label("instance_type", attrs.get("instance_type", "unknown")),
                    label("instance_id", attrs.get("id", "unknown")),
                )
                lines.append("tpiac_terraform_managed_instance{" + ",".join(values) + "} 1")
    lines.append(f"tpiac_terraform_state_parse_errors{{{label('student_vm', STUDENT_VM)}}} {errors}")
    lines.append(f"tpiac_terraform_state_scan_success{{{label('student_vm', STUDENT_VM)}}} 1")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".tpiac_tfstate.", dir=OUTPUT.parent, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write("\n".join(lines) + "\n")
        os.chmod(temporary, 0o644)
        os.replace(temporary, OUTPUT)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
