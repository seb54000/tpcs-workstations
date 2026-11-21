#!/usr/bin/env python3
"""Run the weekly dual-account AMI check and email findings or check failures."""

from __future__ import annotations

from datetime import datetime, timezone
from email.message import EmailMessage
from email.policy import SMTP
from email.utils import formatdate
import fcntl
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / "00-build-image.sh"
STATE_DIR = Path("/var/lib/tpcs-ami-check")
STATE_FILE = STATE_DIR / "status.json"
LOCK_FILE = STATE_DIR / "check.lock"


class CheckError(Exception):
    pass


def recipients_from_env() -> list[str]:
    raw = os.environ.get("TPCS_AMI_ALERT_RECIPIENT", "")
    recipients = [item.strip() for item in raw.split(",") if item.strip()]
    if not recipients or any(not re.fullmatch(r"[^\s@<>]+@[^\s@<>]+", item) for item in recipients):
        raise CheckError("TPCS_AMI_ALERT_RECIPIENT must contain one or more valid email addresses.")
    sender = os.environ.get("TPCS_AMI_ALERT_SENDER", "")
    if not re.fullmatch(r"[^\s@<>]+@[^\s@<>]+", sender):
        raise CheckError("TPCS_AMI_ALERT_SENDER must be a valid email address.")
    return recipients


def write_status(status: str, result: str, findings: int) -> None:
    STATE_DIR.mkdir(mode=0o755, parents=True, exist_ok=True)
    payload = {
        "updatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "status": status,
        "result": result,
        "findingCount": findings,
    }
    fd, temporary = tempfile.mkstemp(prefix=".status.", dir=STATE_DIR)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(payload, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, STATE_FILE)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def send_mail(recipients: list[str], subject: str, body: str) -> None:
    sender = os.environ["TPCS_AMI_ALERT_SENDER"]
    message = EmailMessage(policy=SMTP)
    message["From"] = sender
    message["To"] = ", ".join(recipients)
    message["Subject"] = subject
    message["Date"] = formatdate(localtime=True)
    message.set_content(body)
    try:
        result = subprocess.run(
            ["/usr/bin/msmtp", "--timeout=25", "--", *recipients],
            input=message.as_bytes(), capture_output=True, timeout=35, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        raise CheckError("SMTP alert delivery failed or timed out.") from None
    if result.returncode:
        raise CheckError(f"SMTP alert delivery failed (exit {result.returncode}).")


def run(max_age_days: int) -> int:
    STATE_DIR.mkdir(mode=0o755, parents=True, exist_ok=True)
    with LOCK_FILE.open("a", encoding="utf-8") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise CheckError("Another TPCS AMI check is already running.") from None

        recipients: list[str] = []
        command = [str(WRAPPER), "check", "--max-age-days", str(max_age_days), "--account", "all"]
        try:
            recipients = recipients_from_env()
            result = subprocess.run(command, capture_output=True, text=True, timeout=900, check=False,
                                    cwd=ROOT, env=os.environ.copy())
            output = (result.stdout + "\n" + result.stderr).strip()
            if len(output) > 16000:
                output = output[-16000:]
            if result.returncode == 0:
                write_status("ok", "clean", 0)
                print(output or "No old unused AMIs found.", flush=True)
                return 0
            if result.returncode == 1:
                subject = "[TPCS AMI] Unused AWS AMIs need review"
                result_label = "findings"
                findings = sum(line.startswith("ami-") for line in output.splitlines())
                body = (f"Unused TPCS AMIs older than {max_age_days} days were found.\n"
                        "Review whether they can be removed; this check never deletes images.\n\n"
                        f"Host: {socket.gethostname()}\nChecked: {datetime.now().astimezone().isoformat()}\n\n"
                        f"{output}\n")
            else:
                subject = "[TPCS AMI] AWS catalogue check failed"
                result_label = "check-error"
                findings = 0
                body = ("The weekly TPCS AMI inventory could not complete successfully.\n\n"
                        f"Host: {socket.gethostname()}\nChecked: {datetime.now().astimezone().isoformat()}\n"
                        f"Exit code: {result.returncode}\n\n{output}\n")
            send_mail(recipients, subject, body)
            write_status("ok", result_label, findings)
            print(f"Alert email sent: {result_label}; exit_code={result.returncode}", flush=True)
            return 0
        except subprocess.TimeoutExpired:
            body = ("The weekly TPCS AMI inventory exceeded its 15-minute limit.\n\n"
                    f"Host: {socket.gethostname()}\nChecked: {datetime.now().astimezone().isoformat()}\n")
            try:
                send_mail(recipients, "[TPCS AMI] AWS catalogue check timed out", body)
                write_status("ok", "timeout-alert-sent", 0)
                return 0
            except CheckError as exc:
                write_status("error", "notification-error", 0)
                print(str(exc), file=sys.stderr)
                return 1
        except CheckError as exc:
            # Keep a fresh failure marker for functional monitoring; its mail
            # reports that the scheduled check could not deliver its own alert.
            write_status("error", "notification-error", 0)
            print(str(exc), file=sys.stderr)
            return 1


def main() -> int:
    if os.geteuid() != 0:
        print("Run this scheduled checker as root to use the protected system msmtp configuration.",
              file=sys.stderr)
        return 2
    try:
        return run(int(os.environ.get("TPCS_AMI_MAX_AGE_DAYS", "21")))
    except (CheckError, OSError, ValueError) as exc:
        print(f"TPCS AMI alert error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
