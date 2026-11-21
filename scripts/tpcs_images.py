#!/usr/bin/env python3
"""Manage the TPCS Packer AMI catalogue on the NAS and in AWS."""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import uuid


ROOT = Path(__file__).resolve().parents[1]
PACKER_DIR = ROOT / "packer"
PACKER_MANIFESTS = {
    "student-tpiac": ROOT / "terraform-infra" / ".tpcs" / "packer-student-manifest.json",
    "access-docs": ROOT / "terraform-infra" / ".tpcs" / "packer-access-docs-manifest.json",
}
PACKER_BUILDERS = {"student-tpiac": "student", "access-docs": "access_docs"}
PACKER_IMAGE_PREFIXES = {
    "student-tpiac": "tpcs-student-jammy",
    "access-docs": "tpcs-access-docs-jammy",
}
PACKER_PREFIX_VARS = {
    "student-tpiac": "TPCS_PACKER_STUDENT_AMI_NAME_PREFIX",
    "access-docs": "TPCS_PACKER_ACCESS_DOCS_AMI_NAME_PREFIX",
}
AMI_SLOTS = {
    "student-tpiac": "tpcs-student-tpiac-current",
    "access-docs": "tpcs-access-docs-current",
}
BUCKET = "csexed-iac-image-import"
S3_BASE_PREFIX = "tpcs-ami-catalog"
MANIFEST_VERSION = 1
SUPPORTED_BUILD_PROFILES = set(AMI_SLOTS)


class ImageError(Exception):
    pass


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso_time(value: datetime | None = None) -> str:
    return (value or utc_now()).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_time(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def safe_text(value: str) -> str:
    for name in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"):
        secret = os.environ.get(name)
        if secret:
            value = value.replace(secret, "[REDACTED]")
    return value


def run(command: list[str], *, capture: bool = False, check: bool = True,
        env: dict[str, str] | None = None, timeout: int | None = None) -> subprocess.CompletedProcess:
    result = subprocess.run(
        command,
        check=False,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        env=env or os.environ.copy(),
        timeout=timeout,
    )
    if check and result.returncode:
        details = safe_text((result.stderr or result.stdout or "").strip()) if capture else ""
        raise ImageError(f"Command failed ({result.returncode}): {shlex.join(command[:3])}" +
                         (f" — {details}" if details else ""))
    return result


def aws_json(*args: str, check: bool = True) -> dict:
    command = ["aws", *args, "--output", "json", "--no-cli-pager"]
    result = run(command, capture=True, check=check, timeout=180)
    if result.returncode:
        return {}
    try:
        return json.loads(result.stdout or "{}")
    except json.JSONDecodeError as exc:
        raise ImageError("AWS CLI returned invalid JSON.") from exc


def aws_text(*args: str, check: bool = True) -> str:
    command = ["aws", *args, "--output", "text", "--no-cli-pager"]
    result = run(command, capture=True, check=check, timeout=180)
    if result.returncode:
        return ""
    return (result.stdout or "").strip()


def require_command(name: str) -> None:
    if shutil.which(name) is None:
        raise ImageError(f"Required command not found: {name}")


def catalog_root(*, create: bool = False) -> Path:
    raw = os.environ.get("TPCS_AMI_CATALOG_DIR", "").strip()
    if not raw:
        raise ImageError("Set TPCS_AMI_CATALOG_DIR in the private credentials file.")
    path = Path(raw).expanduser().absolute()
    existing = path
    while not existing.exists() and existing != existing.parent:
        existing = existing.parent
    result = run(["findmnt", "-T", str(existing), "-n", "-o", "FSTYPE"], capture=True,
                 check=False, timeout=10)
    fstype = (result.stdout or "").strip().lower()
    if result.returncode or fstype not in {"cifs", "smb3", "nfs", "nfs4"}:
        raise ImageError(f"Catalog path is not on a mounted NAS filesystem: {path}")
    if create:
        path.mkdir(parents=True, exist_ok=True)
    return path


def slug(value: str, label: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,79}", value):
        raise ImageError(f"Invalid {label}: use letters, digits, dot, underscore or dash.")
    return value


def image_dir(profile: str, generation: str, *, create: bool = False) -> Path:
    profile = slug(profile, "profile")
    generation = slug(generation, "generation")
    directory = catalog_root(create=create) / profile / generation
    if create:
        directory.mkdir(parents=True, exist_ok=True)
    return directory


def read_manifest(profile: str, generation: str) -> tuple[Path, dict]:
    directory = image_dir(profile, generation)
    manifest_path = directory / "manifest.json"
    if not manifest_path.is_file():
        raise ImageError(f"No manifest found for {profile}/{generation}.")
    try:
        manifest = json.loads(manifest_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise ImageError(f"Cannot read manifest: {manifest_path}") from exc
    if manifest.get("manifest_version") != MANIFEST_VERSION:
        raise ImageError("Unsupported catalogue manifest version.")
    return manifest_path, manifest


def write_json_atomic(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(handle, "w") as stream:
            json.dump(value, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(tmp_name, 0o600)
        os.replace(tmp_name, path)
    finally:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(8 * 1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def confirm(question: str, yes: bool) -> None:
    if yes:
        return
    if not sys.stdin.isatty():
        raise ImageError("This operation needs an interactive confirmation; pass --yes to run it unattended.")
    answer = input(f"{question} [y/N] ").strip().lower()
    if answer not in {"y", "yes", "o", "oui"}:
        raise ImageError("Operation cancelled.")


def selected_identity(region: str) -> tuple[str, str]:
    if any(name.startswith("AWS_ENDPOINT_URL") and value for name, value in os.environ.items()):
        raise ImageError("Remove AWS_ENDPOINT_URL overrides before using the image commands.")
    identity = aws_json("sts", "get-caller-identity")
    account_id = str(identity.get("Account", ""))
    expected = os.environ.get("TPCS_EXPECTED_AWS_ACCOUNT_ID", "")
    if not re.fullmatch(r"\d{12}", account_id):
        raise ImageError("STS did not return a valid AWS account ID.")
    if expected and account_id != expected:
        raise ImageError("AWS credentials do not match the configured account alias; operation stopped.")
    alias = os.environ.get("TPCS_AWS_ACCOUNT_ACTIVE", os.environ.get("TPCS_AWS_ACCOUNT", "unknown")).upper()
    print(f"AWS account: {alias} ({account_id}), region {region}")
    return account_id, alias


def image_details(ami_id: str, region: str) -> dict:
    payload = aws_json("ec2", "describe-images", "--region", region,
                       "--owners", "self", "--image-ids", ami_id)
    images = payload.get("Images", [])
    if len(images) != 1:
        raise ImageError(f"AMI {ami_id} is not available to the selected AWS account in {region}.")
    image = images[0]
    root_name = image.get("RootDeviceName")
    root = next((item for item in image.get("BlockDeviceMappings", [])
                 if item.get("DeviceName") == root_name and item.get("Ebs")), None)
    if not root:
        raise ImageError(f"AMI {ami_id} has no EBS root-device mapping.")
    ebs = root["Ebs"]
    if ebs.get("Encrypted"):
        raise ImageError("VM Import/Export cannot export an AMI with an encrypted root snapshot.")
    return {
        "ami_id": ami_id,
        "ami_name": image.get("Name", ""),
        "created_at": image.get("CreationDate"),
        "architecture": image.get("Architecture", "x86_64"),
        "virtualization_type": image.get("VirtualizationType", "hvm"),
        "root_device_name": root_name,
        "root_volume_size_gib": int(ebs.get("VolumeSize", 32)),
        "root_volume_type": ebs.get("VolumeType", "gp3"),
        "root_snapshot_id": ebs.get("SnapshotId", ""),
        "root_encrypted": bool(ebs.get("Encrypted", False)),
        "ena_support": bool(image.get("EnaSupport", False)),
        "boot_mode": image.get("BootMode") or "legacy-bios",
    }


def ensure_bucket(region: str) -> bool:
    """Return whether this command created the dedicated VM Import bucket."""
    head = run(["aws", "s3api", "head-bucket", "--bucket", BUCKET], capture=True,
               check=False, timeout=30)
    if head.returncode == 0:
        location = aws_json("s3api", "get-bucket-location", "--bucket", BUCKET).get("LocationConstraint")
        location = location or "us-east-1"
        if location != region:
            raise ImageError(f"S3 bucket {BUCKET} is in {location}, expected {region}.")
        return False
    error_text = (head.stderr or "")
    if "404" not in error_text and "Not Found" not in error_text and "NoSuchBucket" not in error_text:
        raise ImageError(f"Cannot access S3 bucket {BUCKET}; refusing to create or modify it.")
    command = ["aws", "s3api", "create-bucket", "--bucket", BUCKET, "--region", region]
    if region != "us-east-1":
        command.extend(["--create-bucket-configuration", f"LocationConstraint={region}"])
    run(command)
    run(["aws", "s3api", "put-public-access-block", "--bucket", BUCKET,
         "--public-access-block-configuration",
         "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"])
    run(["aws", "s3api", "put-bucket-encryption", "--bucket", BUCKET,
         "--server-side-encryption-configuration",
         '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'])
    return True


def clean_s3_prefix(region: str, prefix: str, bucket_created: bool) -> None:
    run(["aws", "s3", "rm", f"s3://{BUCKET}/{prefix}", "--recursive"], check=False)
    if not bucket_created:
        return
    payload = aws_json("s3api", "list-objects-v2", "--bucket", BUCKET)
    keys = [item["Key"] for item in payload.get("Contents", [])]
    marker = "vmimportexport_write_verification.txt"
    if marker in keys:
        run(["aws", "s3api", "delete-object", "--bucket", BUCKET, "--key", marker])
        keys.remove(marker)
    if keys:
        print(f"Temporary bucket retained because unrelated objects remain: {BUCKET}", file=sys.stderr)
        return
    run(["aws", "s3api", "delete-bucket", "--bucket", BUCKET, "--region", region], check=False)


def wait_export(task_id: str, region: str) -> dict:
    deadline = time.monotonic() + int(os.environ.get("TPCS_AMI_TASK_TIMEOUT_SECONDS", "14400"))
    last_progress = None
    while time.monotonic() < deadline:
        payload = aws_json("ec2", "describe-export-image-tasks", "--region", region,
                           "--export-image-task-ids", task_id)
        tasks = payload.get("ExportImageTasks", [])
        if not tasks:
            raise ImageError(f"AWS no longer reports export task {task_id}.")
        task = tasks[0]
        state = task.get("Status", "unknown")
        progress = task.get("Progress", "")
        if progress != last_progress or state != "active":
            print(f"Export {task_id}: {state} {progress}% {task.get('StatusMessage', '')}".strip())
            last_progress = progress
        if state == "completed":
            return task
        if state in {"deleted", "cancelled", "failed"}:
            raise ImageError(f"AMI export failed: {task.get('StatusMessage', state)}")
        time.sleep(30)
    raise ImageError(f"Timed out while waiting for AMI export {task_id}.")


def wait_snapshot(task_id: str, region: str) -> str:
    deadline = time.monotonic() + int(os.environ.get("TPCS_AMI_TASK_TIMEOUT_SECONDS", "14400"))
    last_progress = None
    while time.monotonic() < deadline:
        payload = aws_json("ec2", "describe-import-snapshot-tasks", "--region", region,
                           "--import-task-ids", task_id)
        tasks = payload.get("ImportSnapshotTasks", [])
        if not tasks:
            raise ImageError(f"AWS no longer reports snapshot import {task_id}.")
        detail = tasks[0].get("SnapshotTaskDetail", {})
        state = detail.get("Status", "unknown")
        progress = detail.get("Progress", "")
        if progress != last_progress or state != "active":
            print(f"Snapshot import {task_id}: {state} {progress}% {detail.get('StatusMessage', '')}".strip())
            last_progress = progress
        if state == "completed" and detail.get("SnapshotId"):
            return detail["SnapshotId"]
        if state in {"deleted", "cancelled", "error", "failed"}:
            raise ImageError(f"Snapshot import failed: {detail.get('StatusMessage', state)}")
        time.sleep(30)
    raise ImageError(f"Timed out while waiting for snapshot import {task_id}.")


def create_manifest(profile: str, generation: str, account_id: str, account_alias: str,
                    region: str, details: dict) -> dict:
    return {
        "manifest_version": MANIFEST_VERSION,
        "profile": profile,
        "generation": generation,
        "status": "candidate",
        "created_at": iso_time(),
        "region": region,
        "architecture": details.get("architecture", "x86_64"),
        "virtualization_type": details.get("virtualization_type", "hvm"),
        "root_device_name": details.get("root_device_name", "/dev/sda1"),
        "root_volume_size_gib": int(details.get("root_volume_size_gib", 32)),
        "root_volume_type": details.get("root_volume_type", "gp3"),
        "root_encrypted": bool(details.get("root_encrypted", False)),
        "ena_support": bool(details.get("ena_support", False)),
        "boot_mode": details.get("boot_mode", "legacy-bios"),
        "source": {
            "account_id": account_id,
            "account_alias": account_alias,
            "ami_id": details.get("ami_id"),
            "ami_name": details.get("ami_name", ""),
            "ami_created_at": details.get("created_at"),
        },
        "artifact": {"filename": "image.vmdk", "format": "VMDK"},
        "aws_images": [],
    }


def record_aws_image(manifest: dict, details: dict, region: str,
                     account_id: str, account_alias: str, source: str) -> None:
    images = [item for item in manifest.get("aws_images", [])
              if item.get("account_id") != account_id or item.get("ami_id") != details["ami_id"]]
    images.append({
        "account_alias": account_alias,
        "account_id": account_id,
        "region": region,
        "ami_id": details["ami_id"],
        "snapshot_id": details.get("root_snapshot_id", ""),
        "registered_at": details.get("created_at") or iso_time(),
        "state": "available",
        "source": source,
    })
    manifest["aws_images"] = images


def store_backup(profile: str, generation: str, details: dict, region: str,
                 account_id: str, account_alias: str, yes: bool) -> tuple[Path, dict]:
    directory = image_dir(profile, generation, create=True)
    artifact = directory / "image.vmdk"
    manifest_path = directory / "manifest.json"
    if artifact.exists():
        raise ImageError(f"Refusing to overwrite existing catalogue artifact: {artifact}")
    confirm(f"Export {details['ami_id']} from {account_alias} and store it in {directory}?", yes)
    bucket_created = ensure_bucket(region)
    prefix = f"{S3_BASE_PREFIX}/{profile}/{generation}/{uuid.uuid4().hex}/"
    task_id = ""
    started = time.monotonic()
    try:
        result = aws_json("ec2", "export-image", "--region", region, "--image-id", details["ami_id"],
                          "--disk-image-format", "VMDK", "--s3-export-location",
                          f"S3Bucket={BUCKET},S3Prefix={prefix}", "--description",
                          f"TPCS {profile} {generation} NAS catalogue export")
        task_id = result.get("ExportImageTaskId", "")
        if not task_id:
            raise ImageError("AWS did not return an export task ID.")
        task = wait_export(task_id, region)
        key = f"{prefix}export-ami-{task_id}.vmdk"
        partial = directory / ".image.vmdk.partial"
        print(f"Downloading S3 artifact to NAS: {artifact}")
        run(["aws", "s3", "cp", f"s3://{BUCKET}/{key}", str(partial), "--only-show-errors"])
        os.replace(partial, artifact)
        size = artifact.stat().st_size
        checksum = sha256_file(artifact)
        if manifest_path.is_file():
            try:
                manifest = json.loads(manifest_path.read_text())
            except (OSError, json.JSONDecodeError) as exc:
                raise ImageError(f"Cannot update existing manifest: {manifest_path}") from exc
            if manifest.get("profile") != profile or manifest.get("generation") != generation:
                raise ImageError("Existing manifest does not match the requested profile/generation.")
            manifest["region"] = region
            manifest["source"] = {
                **manifest.get("source", {}),
                "account_id": account_id,
                "account_alias": account_alias,
                "ami_id": details["ami_id"],
                "ami_name": details.get("ami_name", ""),
                "ami_created_at": details.get("created_at"),
                "export_task_id": task_id,
            }
        else:
            manifest = create_manifest(profile, generation, account_id, account_alias, region, details)
            manifest["source"]["export_task_id"] = task_id
        manifest["source"]["export_task_id"] = task_id
        manifest["artifact"].update({"size_bytes": size, "sha256": checksum})
        manifest["timings_seconds"] = {"export_and_download": round(time.monotonic() - started)}
        write_json_atomic(manifest_path, manifest)
        print(f"NAS catalogue artifact ready: {artifact} ({size} bytes, sha256 {checksum})")
        return manifest_path, manifest
    except Exception:
        partial = directory / ".image.vmdk.partial"
        if partial.exists():
            partial.unlink()
        raise
    finally:
        clean_s3_prefix(region, prefix, bucket_created)


def build(args: argparse.Namespace, region: str, account_id: str, account_alias: str) -> None:
    profile = args.profile
    if profile not in SUPPORTED_BUILD_PROFILES:
        supported = ", ".join(sorted(SUPPORTED_BUILD_PROFILES))
        raise ImageError(f"Packer build is currently implemented for: {supported}.")
    for command in ("packer", "ansible-playbook", "ansible-doc"):
        require_command(command)
    if run(["ansible-doc", "-t", "module", "community.general.snap"], capture=True,
           check=False).returncode:
        raise ImageError("community.general.snap is unavailable in the active Ansible environment.")

    generation = args.generation or f"{profile}-{utc_now().strftime('%Y%m%d-%H%M%S')}"
    slug(generation, "generation")
    directory = image_dir(profile, generation, create=True)
    if (directory / "manifest.json").exists() or (directory / "image.vmdk").exists():
        raise ImageError(f"Catalogue generation already exists: {profile}/{generation}")
    confirm(f"Build and archive {profile}/{generation} in {account_alias} ({account_id})?", args.yes)

    builder = PACKER_BUILDERS[profile]
    packer_manifest = PACKER_MANIFESTS[profile]
    env = os.environ.copy()
    env.update({
        "PKR_VAR_aws_region": region,
        "PKR_VAR_source_ami": os.environ.get("TPCS_PACKER_SOURCE_AMI", "ami-01d21b7be69801c2f"),
        "PKR_VAR_build_instance_type": os.environ.get("TPCS_PACKER_BUILD_INSTANCE_TYPE", "m5.large"),
        "PKR_VAR_subnet_id": os.environ.get("TPCS_PACKER_SUBNET_ID", ""),
        "PKR_VAR_ami_name_prefix": os.environ.get(
            PACKER_PREFIX_VARS[profile], PACKER_IMAGE_PREFIXES[profile]),
        "PKR_VAR_image_generation": generation,
    })
    print(f"Packer build profile: {profile}; generation: {generation}")
    run(["packer", "init", "."], env=env)
    run(["packer", "validate", "."], env=env)
    packer_manifest.parent.mkdir(parents=True, exist_ok=True)
    packer_manifest.unlink(missing_ok=True)
    run(["packer", "build", f"-only=amazon-ebs.{builder}", "."], env=env)
    try:
        packer_data = json.loads(packer_manifest.read_text())
        ami_id = packer_data["builds"][-1]["artifact_id"].split(":")[-1]
    except (OSError, json.JSONDecodeError, KeyError, IndexError) as exc:
        raise ImageError("Could not read the Packer manifest to determine the AMI ID.") from exc
    if not re.fullmatch(r"ami-[0-9a-f]{8,17}", ami_id):
        raise ImageError("Packer manifest did not contain a valid AMI ID.")

    details = image_details(ami_id, region)
    manifest = create_manifest(profile, generation, account_id, account_alias, region, details)
    manifest["build"] = {
        "packer_version": run(["packer", "version"], capture=True).stdout.strip(),
        "repository": "tpcs-workstations",
        "status": "candidate-built",
    }
    write_json_atomic(directory / "manifest.json", manifest)
    print(f"Packer candidate created: {ami_id}; exporting it to the NAS catalogue.")
    manifest_path, manifest = store_backup(profile, generation, details, region,
                                           account_id, account_alias, True)
    result = aws_json("ec2", "deregister-image", "--region", region, "--image-id", ami_id,
                      "--delete-associated-snapshots")
    for snapshot in result.get("DeleteSnapshotResults", []):
        if snapshot.get("ReturnCode") != "success":
            print(f"Temporary Packer snapshot cleanup needs review: {snapshot.get('SnapshotId')} "
                  f"({snapshot.get('ReturnCode')})", file=sys.stderr)
    manifest["status"] = "archived-candidate"
    manifest["build"]["status"] = "built-archived-temporary-ami-removed"
    write_json_atomic(manifest_path, manifest)
    print(f"Archived {profile}/{generation}; temporary AMI removed from AWS. "
          f"Use restore to replace {AMI_SLOTS[profile]} when this generation is selected.")


def backup(args: argparse.Namespace, region: str, account_id: str, account_alias: str) -> None:
    profile = args.profile
    generation = args.generation or f"{profile}-{utc_now().strftime('%Y%m%d-%H%M%S')}"
    slug(generation, "generation")
    details = image_details(args.ami_id, region)
    image_tags = tag_map(aws_json("ec2", "describe-images", "--region", region,
                                  "--owners", "self", "--image-ids", args.ami_id)["Images"][0])
    if image_tags.get("Repository") != "tpcs-workstations":
        raise ImageError("Refusing to archive an AMI without Repository=tpcs-workstations.")
    manifest_path, manifest = store_backup(profile, generation, details, region,
                                           account_id, account_alias, args.yes)
    record_aws_image(manifest, details, region, account_id, account_alias, "AWS backup")
    write_json_atomic(manifest_path, manifest)
    print(f"Catalogue manifest: {manifest_path}")


def restore(args: argparse.Namespace, region: str, account_id: str, account_alias: str) -> None:
    manifest_path, manifest = read_manifest(args.profile, args.generation)
    if args.profile not in AMI_SLOTS:
        raise ImageError(f"No AWS current-image slot is configured for profile {args.profile}.")
    artifact = manifest_path.parent / manifest["artifact"].get("filename", "image.vmdk")
    if not artifact.is_file():
        raise ImageError(f"NAS image file is missing: {artifact}")
    actual_hash = sha256_file(artifact)
    expected_hash = manifest.get("artifact", {}).get("sha256")
    if expected_hash and actual_hash != expected_hash:
        raise ImageError("NAS image checksum does not match its manifest.")
    if manifest.get("region") != region:
        raise ImageError(f"Image region is {manifest.get('region')}, selected AWS region is {region}.")
    existing = current_slot_image(args.profile, region)
    existing_id = existing.get("ImageId") if existing else None
    existing_generation = tag_map(existing).get("TPCSImageGeneration", "unknown") if existing else None
    action = (f"replace current {args.profile} AMI {existing_id} ({existing_generation})"
              if existing else f"install the first current {args.profile} AMI")
    confirm(f"Restore {args.profile}/{args.generation} into {action} for {account_alias} ({account_id})?",
            args.yes)

    bucket_created = ensure_bucket(region)
    prefix = f"{S3_BASE_PREFIX}/{args.profile}/{args.generation}/{uuid.uuid4().hex}/"
    key = f"{prefix}{artifact.name}"
    import_task = ""
    snapshot_id = ""
    registered_ami = ""
    old_snapshot_id = ""
    old_details: dict | None = None
    started = time.monotonic()
    try:
        print(f"Uploading NAS artifact to s3://{BUCKET}/{key}")
        run(["aws", "s3", "cp", str(artifact), f"s3://{BUCKET}/{key}",
             "--only-show-errors", "--checksum-algorithm", "SHA256"])
        container = f"Format=VMDK,UserBucket={{S3Bucket={BUCKET},S3Key={key}}}"
        payload = aws_json("ec2", "import-snapshot", "--region", region, "--description",
                           f"TPCS {args.profile} {args.generation} restored from NAS",
                           "--disk-container", container)
        import_task = payload.get("ImportTaskId", "")
        if not import_task:
            raise ImageError("AWS did not return an ImportSnapshot task ID.")
        snapshot_id = wait_snapshot(import_task, region)
        image_name = AMI_SLOTS[args.profile]
        image_tags = {
            "Name": image_name,
            "Repository": "tpcs-workstations",
            "ManagedBy": "TPCSImageCatalog",
            "TPCSManaged": "true",
            "TPCSImageProfile": args.profile,
            "TPCSImageGeneration": args.generation,
            "TPCSImageSource": "NAS",
            "TPCSImageSlot": "current",
            "TPCSImageCreatedAt": iso_time(),
        }
        snapshot_tag_args = ["ec2", "create-tags", "--region", region, "--resources", snapshot_id,
                             "--tags", json.dumps([{"Key": key_name, "Value": value}
                                                   for key_name, value in image_tags.items()])]
        run(snapshot_tag_args)

        if existing:
            old_details = image_details(existing["ImageId"], region)
            old_snapshot_id = old_details.get("root_snapshot_id", "")
            print(f"Deregistering current AMI {existing['ImageId']} to free its fixed name.")
            aws_json("ec2", "deregister-image", "--region", region, "--image-id", existing["ImageId"])

        details = {
            "architecture": manifest.get("architecture", "x86_64"),
            "virtualization_type": manifest.get("virtualization_type", "hvm"),
            "root_device_name": manifest.get("root_device_name", "/dev/sda1"),
            "root_volume_size_gib": int(manifest.get("root_volume_size_gib", 32)),
            "root_volume_type": manifest.get("root_volume_type", "gp3"),
            "boot_mode": manifest.get("boot_mode") or "legacy-bios",
            "ena_support": bool(manifest.get("ena_support")),
        }
        try:
            registered_ami = register_snapshot_as_ami(snapshot_id, image_name, args.generation,
                                                      details, region)
            wait_image_available(registered_ami, region)
            tag_args = ["ec2", "create-tags", "--region", region, "--resources", registered_ami,
                        snapshot_id, "--tags", json.dumps([{"Key": key_name, "Value": value}
                                                            for key_name, value in image_tags.items()])]
            run(tag_args)
        except Exception as register_error:
            if registered_ami:
                run(["aws", "ec2", "deregister-image", "--region", region,
                     "--image-id", registered_ami], check=False)
                registered_ami = ""
            if existing and old_snapshot_id and old_details:
                try:
                    print("Restoring the previous current AMI after replacement failed.", file=sys.stderr)
                    rollback_id = register_snapshot_as_ami(
                        old_snapshot_id, image_name, existing_generation or "previous", old_details, region)
                    wait_image_available(rollback_id, region)
                    old_tags = tag_map(existing)
                    run(["ec2", "create-tags", "--region", region, "--resources", rollback_id,
                         old_snapshot_id, "--tags", json.dumps([{"Key": key_name, "Value": value}
                                                               for key_name, value in old_tags.items()])])
                    print(f"Previous current AMI restored as {rollback_id}.", file=sys.stderr)
                except Exception as rollback_error:
                    print(f"AMI rollback also failed; old snapshot retained as {old_snapshot_id}: "
                          f"{safe_text(str(rollback_error))}", file=sys.stderr)
            raise register_error

        if old_snapshot_id and old_snapshot_id != snapshot_id:
            result = run(["aws", "ec2", "delete-snapshot", "--region", region,
                          "--snapshot-id", old_snapshot_id], capture=True, check=False)
            if result.returncode:
                print(f"Old current snapshot cleanup needs review: {old_snapshot_id} "
                      f"({safe_text(result.stderr or 'delete failed').strip()})", file=sys.stderr)

        if existing and existing_generation:
            mark_catalog_aws_state(args.profile, existing_generation, account_id,
                                   existing["ImageId"], "replaced")
        cleanup_profile_images(args.profile, registered_ami, region, account_id)

        entry = {
            "account_alias": account_alias,
            "account_id": account_id,
            "region": region,
            "ami_id": registered_ami,
            "snapshot_id": snapshot_id,
            "registered_at": iso_time(),
            "state": "available",
            "timings_seconds": {"upload_and_import_snapshot": round(time.monotonic() - started)},
        }
        images = []
        for item in manifest.get("aws_images", []):
            if item.get("account_id") == account_id and item.get("state") == "available":
                item["state"] = "replaced"
                item["replaced_at"] = iso_time()
            images.append(item)
        images.append(entry)
        manifest["aws_images"] = images
        manifest["status"] = "current-in-aws"
        write_json_atomic(manifest_path, manifest)
        print(f"Current AMI ready: {registered_ami}; name {image_name}; generation {args.generation}. "
              f"Existing EC2 instances continue using their current volumes.")
    except Exception:
        if registered_ami:
            print(f"AMI {registered_ami} was registered; inspect it before retrying.", file=sys.stderr)
        elif snapshot_id:
            print(f"Imported snapshot retained for recovery/retry: {snapshot_id}", file=sys.stderr)
        raise
    finally:
        clean_s3_prefix(region, prefix, bucket_created)


def register_snapshot_as_ami(snapshot_id: str, image_name: str, generation: str,
                             details: dict, region: str) -> str:
    root_name = details.get("root_device_name", "/dev/sda1")
    mapping = json.dumps([{"DeviceName": root_name, "Ebs": {
        "SnapshotId": snapshot_id,
        "DeleteOnTermination": True,
        "VolumeSize": int(details.get("root_volume_size_gib", 32)),
        "VolumeType": details.get("root_volume_type", "gp3"),
    }}])
    register_args = ["ec2", "register-image", "--region", region, "--name", image_name,
                     "--description", f"TPCS {generation}; current profile AMI",
                     "--architecture", details.get("architecture", "x86_64"),
                     "--virtualization-type", details.get("virtualization_type", "hvm"),
                     "--root-device-name", root_name, "--block-device-mappings", mapping,
                     "--boot-mode", details.get("boot_mode") or "legacy-bios"]
    if details.get("ena_support"):
        register_args.append("--ena-support")
    deadline = time.monotonic() + 300
    while True:
        try:
            image_id = aws_json(*register_args).get("ImageId", "")
            if re.fullmatch(r"ami-[0-9a-f]{8,17}", image_id):
                return image_id
            raise ImageError("AWS did not return a valid registered AMI ID.")
        except ImageError as exc:
            if "InvalidAMIName.Duplicate" not in str(exc) or time.monotonic() >= deadline:
                raise
            print("AWS is still propagating the previous AMI deregistration; retrying registration.")
            time.sleep(10)


def wait_image_available(ami_id: str, region: str) -> None:
    deadline = time.monotonic() + 600
    while time.monotonic() < deadline:
        payload = aws_json("ec2", "describe-images", "--region", region,
                           "--owners", "self", "--image-ids", ami_id)
        images = payload.get("Images", [])
        state = images[0].get("State") if images else "missing"
        if state == "available":
            return
        if state in {"failed", "error", "deregistered", "missing"}:
            raise ImageError(f"Registered AMI {ami_id} entered unexpected state {state}.")
        print(f"Waiting for AMI {ami_id}: {state}")
        time.sleep(10)
    raise ImageError(f"Timed out waiting for AMI {ami_id} to become available.")


def current_slot_image(profile: str, region: str) -> dict | None:
    image_name = AMI_SLOTS.get(profile)
    if not image_name:
        return None
    payload = aws_json("ec2", "describe-images", "--region", region, "--owners", "self",
                       "--filters", f"Name=name,Values={image_name}",
                       "Name=tag:Repository,Values=tpcs-workstations",
                       f"Name=tag:TPCSImageProfile,Values={profile}",
                       "Name=state,Values=available")
    images = payload.get("Images", [])
    if len(images) > 1:
        raise ImageError(f"Multiple current AMIs found for profile {profile}; refusing replacement.")
    return images[0] if images else None


def mark_catalog_aws_state(profile: str, generation: str, account_id: str,
                           ami_id: str, state: str) -> None:
    try:
        manifest_path, manifest = read_manifest(profile, generation)
    except ImageError:
        return
    changed = False
    for item in manifest.get("aws_images", []):
        if item.get("account_id") == account_id and item.get("ami_id") == ami_id:
            item["state"] = state
            item["replaced_at"] = iso_time()
            changed = True
    if changed:
        write_json_atomic(manifest_path, manifest)


def cleanup_profile_images(profile: str, keep_ami_id: str, region: str,
                           account_id: str) -> None:
    for image in aws_images(region):
        tags = tag_map(image)
        ami_id = image.get("ImageId", "")
        if ami_id == keep_ami_id or tags.get("TPCSImageProfile") != profile:
            continue
        print(f"Removing superseded TPCS AMI {ami_id} ({image.get('Name', '')}).")
        result = aws_json("ec2", "deregister-image", "--region", region,
                          "--image-id", ami_id, "--delete-associated-snapshots")
        for item in result.get("DeleteSnapshotResults", []):
            if item.get("ReturnCode") != "success":
                print(f"Superseded snapshot cleanup needs review: {item.get('SnapshotId')} "
                      f"({item.get('ReturnCode')})", file=sys.stderr)
        generation = tags.get("TPCSImageGeneration", "")
        if generation:
            mark_catalog_aws_state(profile, generation, account_id, ami_id, "replaced")


def tag_map(image: dict) -> dict[str, str]:
    return {tag.get("Key", ""): tag.get("Value", "") for tag in image.get("Tags", [])}


def aws_images(region: str) -> list[dict]:
    payload = aws_json("ec2", "describe-images", "--region", region, "--owners", "self",
                       "--filters", "Name=tag:Repository,Values=tpcs-workstations")
    return sorted(payload.get("Images", []), key=lambda image: image.get("CreationDate", ""), reverse=True)


def images_used_by_instances(region: str) -> set[str]:
    payload = aws_json("ec2", "describe-instances", "--region", region, "--filters",
                       "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down")
    return {instance.get("ImageId", "")
            for reservation in payload.get("Reservations", [])
            for instance in reservation.get("Instances", [])}


def list_aws(region: str) -> None:
    images = aws_images(region)
    used = images_used_by_instances(region)
    if not images:
        print("No TPCS-owned AMIs found in this AWS account.")
        return
    print("AMI ID\tCREATED\tPROFILE\tGENERATION\tIN USE\tNAME")
    for image in images:
        tags = tag_map(image)
        print("\t".join([
            image.get("ImageId", ""), image.get("CreationDate", ""),
            tags.get("TPCSImageProfile", tags.get("Role", "")),
            tags.get("TPCSImageGeneration", ""),
            "yes" if image.get("ImageId") in used else "no",
            image.get("Name", ""),
        ]))


def list_nas() -> None:
    root = catalog_root()
    manifests = sorted(root.glob("*/*/manifest.json")) if root.exists() else []
    if not manifests:
        print(f"No catalogue images found under {root}.")
        return
    print("PROFILE\tGENERATION\tSTATUS\tSIZE\tSHA256\tAWS COPIES")
    for path in manifests:
        try:
            manifest = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            print(f"Invalid manifest: {path}", file=sys.stderr)
            continue
        artifact = path.parent / manifest.get("artifact", {}).get("filename", "image.vmdk")
        copies = ",".join(f"{item.get('account_alias')}:{item.get('ami_id')}"
                          for item in manifest.get("aws_images", []) if item.get("state") == "available")
        print("\t".join([
            manifest.get("profile", path.parent.parent.name),
            manifest.get("generation", path.parent.name),
            manifest.get("status", "unknown"),
            str(artifact.stat().st_size if artifact.is_file() else "missing"),
            manifest.get("artifact", {}).get("sha256", ""), copies,
        ]))


def check_old(args: argparse.Namespace, region: str) -> int:
    used = images_used_by_instances(region)
    threshold = utc_now() - timedelta(days=args.max_age_days)
    findings = []
    for image in aws_images(region):
        created = parse_time(image["CreationDate"])
        if created >= threshold or image.get("ImageId") in used:
            continue
        tags = tag_map(image)
        findings.append((image, tags))
    if not findings:
        print(f"No unused TPCS AMIs older than {args.max_age_days} days in this account.")
        return 0
    print(f"Unused TPCS AMIs older than {args.max_age_days} days:")
    for image, tags in findings:
        print("\t".join([image.get("ImageId", ""), image.get("CreationDate", ""),
                         tags.get("TPCSImageGeneration", ""), image.get("Name", "")]))
    print("Review these AMIs and remove them with the delete command after confirming the TP is over.")
    return 1


def find_manifest_for_ami(profile: str, generation: str, account_id: str,
                          ami_id: str | None = None) -> tuple[Path | None, dict | None]:
    if generation:
        path, manifest = read_manifest(profile, generation)
        entry = next((item for item in manifest.get("aws_images", [])
                      if item.get("account_id") == account_id and item.get("state") == "available" and
                      (ami_id is None or item.get("ami_id") == ami_id)), None)
        return path, manifest if entry else None
    if ami_id:
        root = catalog_root()
        for path in root.glob("*/*/manifest.json"):
            try:
                manifest = json.loads(path.read_text())
            except (OSError, json.JSONDecodeError):
                continue
            if any(item.get("account_id") == account_id and item.get("ami_id") == ami_id
                   and item.get("state") == "available" for item in manifest.get("aws_images", [])):
                return path, manifest
    return None, None


def delete_image(args: argparse.Namespace, region: str, account_id: str, yes: bool) -> None:
    ami_id = args.ami_id
    if sum(bool(value) for value in (args.current, args.generation, ami_id)) != 1:
        raise ImageError("Choose exactly one of --current, --generation or --ami-id.")
    if args.current:
        current = current_slot_image(args.profile, region)
        if not current:
            raise ImageError(f"No current AMI found for profile {args.profile}.")
        ami_id = current["ImageId"]
    if args.current:
        manifest_path, manifest = None, None
    else:
        manifest_path, manifest = find_manifest_for_ami(args.profile, args.generation or "", account_id, ami_id)
    if not ami_id and manifest:
        entry = next(item for item in manifest["aws_images"]
                     if item.get("account_id") == account_id and item.get("state") == "available")
        ami_id = entry["ami_id"]
    if not ami_id:
        raise ImageError("Specify --current, --generation (with --profile) or --ami-id.")
    payload = aws_json("ec2", "describe-images", "--region", region, "--owners", "self", "--image-ids", ami_id)
    images = payload.get("Images", [])
    if len(images) != 1:
        raise ImageError(f"AMI {ami_id} is not owned by the selected AWS account.")
    tags = tag_map(images[0])
    if tags.get("Repository") != "tpcs-workstations":
        raise ImageError("Refusing to deregister an AMI without Repository=tpcs-workstations.")
    used = ami_id in images_used_by_instances(region)
    if used and not args.force_in_use:
        raise ImageError("AMI is referenced by a non-terminated EC2 instance; use --force-in-use only after review.")
    confirm(f"Deregister {ami_id} and delete its associated snapshot(s)?", yes)
    result = aws_json("ec2", "deregister-image", "--region", region, "--image-id", ami_id,
                      "--delete-associated-snapshots")
    for snap in result.get("DeleteSnapshotResults", []):
        if snap.get("ReturnCode") != "success":
            print(f"Snapshot cleanup needs review: {snap.get('SnapshotId')} ({snap.get('ReturnCode')})",
                  file=sys.stderr)
    if manifest_path and manifest:
        for item in manifest.get("aws_images", []):
            if item.get("account_id") == account_id and item.get("ami_id") == ami_id:
                item["state"] = "deleted"
                item["deleted_at"] = iso_time()
        write_json_atomic(manifest_path, manifest)
    print(f"Deregistered {ami_id} in account {account_id}.")


def add_common_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--account", default=os.environ.get("TPCS_AWS_ACCOUNT_ACTIVE", "ECOLE"))
    parser.add_argument("--region", default=os.environ.get("AWS_DEFAULT_REGION", "eu-west-3"))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    build_parser = commands.add_parser("build", help="Build with Packer in AWS and archive to the NAS")
    build_parser.add_argument("--profile", default="student-tpiac",
                             choices=sorted(SUPPORTED_BUILD_PROFILES),
                             help="Image role: student-tpiac or access-docs")
    build_parser.add_argument("--generation", help="Optional NAS version label; auto-generated by default")
    build_parser.add_argument("--yes", action="store_true")
    add_common_options(build_parser)

    backup_parser = commands.add_parser("backup", help="Export an existing AWS AMI to the NAS catalogue")
    backup_parser.add_argument("--ami-id", required=True)
    backup_parser.add_argument("--profile", default="student-tpiac",
                               help="Image role represented in the NAS catalogue")
    backup_parser.add_argument("--generation", help="Optional NAS version label; auto-generated by default")
    backup_parser.add_argument("--yes", action="store_true")
    add_common_options(backup_parser)

    restore_parser = commands.add_parser("restore", help="Upload a NAS image and register it as an AWS AMI")
    restore_parser.add_argument("--profile", required=True)
    restore_parser.add_argument("--generation", required=True,
                                help="Exact NAS generation to install in the fixed AWS current-image slot")
    restore_parser.add_argument("--yes", action="store_true")
    add_common_options(restore_parser)

    delete_parser = commands.add_parser("delete", help="Deregister an image and remove its snapshot")
    delete_parser.add_argument("--profile", default="student-tpiac")
    delete_parser.add_argument("--generation")
    delete_parser.add_argument("--current", action="store_true",
                               help="Delete the fixed current AWS AMI for this profile")
    delete_parser.add_argument("--ami-id")
    delete_parser.add_argument("--force-in-use", action="store_true")
    delete_parser.add_argument("--yes", action="store_true")
    add_common_options(delete_parser)

    list_parser = commands.add_parser("list", help="List the NAS catalogue or current AWS AMIs")
    list_parser.add_argument("source", choices=["nas", "aws"])
    add_common_options(list_parser)

    check_parser = commands.add_parser("check", help="Report old TPCS AMIs not referenced by EC2 instances")
    check_parser.add_argument("--max-age-days", type=int, default=21)
    add_common_options(check_parser)
    return parser.parse_args()


def main() -> int:
    try:
        args = parse_args()
        if args.command == "list" and args.source == "nas":
            list_nas()
            return 0
        require_command("aws")
        account_id, account_alias = selected_identity(args.region)
        # S3 bucket names are global, so keep the short-lived transfer bucket
        # distinct when the same MeLE manages both AWS accounts.
        global BUCKET
        BUCKET = f"{BUCKET}-{account_id}"
        if args.command == "build":
            build(args, args.region, account_id, account_alias)
            return 0
        if args.command == "backup":
            if not args.generation:
                args.generation = f"{args.profile}-{utc_now().strftime('%Y%m%d-%H%M%S')}"
            backup(args, args.region, account_id, account_alias)
            return 0
        if args.command == "restore":
            restore(args, args.region, account_id, account_alias)
            return 0
        if args.command == "delete":
            delete_image(args, args.region, account_id, args.yes)
            return 0
        if args.command == "list" and args.source == "aws":
            list_aws(args.region)
            return 0
        if args.command == "check":
            if args.max_age_days < 1:
                raise ImageError("--max-age-days must be at least 1.")
            return check_old(args, args.region)
        raise ImageError("Unknown command.")
    except (ImageError, OSError, subprocess.SubprocessError) as exc:
        print(f"AMI catalog error: {safe_text(str(exc))}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
