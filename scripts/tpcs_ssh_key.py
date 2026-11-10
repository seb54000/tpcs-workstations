#!/usr/bin/env python3
"""Materialize and validate the TP VM SSH key without printing private data."""
import base64
import binascii
import os
from pathlib import Path
import subprocess
import sys
import tempfile


class KeyError(Exception):
    pass


def public_parts(private_key):
    try:
        result = subprocess.run(
            ['ssh-keygen', '-y', '-f', str(private_key)],
            stdin=subprocess.DEVNULL, capture_output=True, text=True,
            timeout=15, check=True,
        )
    except (OSError, subprocess.SubprocessError):
        raise KeyError('The TP SSH private key is invalid or password-protected.') from None
    parts = result.stdout.strip().split()
    if len(parts) < 2 or not parts[0].startswith(('ssh-', 'ecdsa-', 'sk-')):
        raise KeyError('ssh-keygen returned an invalid TP public key.')
    return tuple(parts[:2])


def read_public(path):
    try:
        parts = path.read_text().strip().split()
    except OSError:
        raise KeyError('Cannot read the existing TP SSH public key.') from None
    if len(parts) < 2:
        raise KeyError('The existing TP SSH public key is invalid.')
    return tuple(parts[:2])


def write_atomic(path, content, mode):
    handle, temporary = tempfile.mkstemp(prefix=f'.{path.name}.', dir=path.parent)
    try:
        os.fchmod(handle, mode)
        with os.fdopen(handle, 'wb') as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except Exception:
        try:
            os.close(handle)
        except OSError:
            pass
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def decode_secret(encoded):
    if len(encoded) > 100_000:
        raise KeyError('TPCS_SSH_PRIVATE_KEY_B64 is unexpectedly large.')
    try:
        raw = base64.b64decode(''.join(encoded.split()), validate=True)
    except (ValueError, binascii.Error):
        raise KeyError('TPCS_SSH_PRIVATE_KEY_B64 is not valid base64.') from None
    if not raw or len(raw) > 64 * 1024 or b'PRIVATE KEY' not in raw:
        raise KeyError('TPCS_SSH_PRIVATE_KEY_B64 does not contain an SSH private key.')
    return raw


def materialize(directory, encoded):
    directory = Path(directory)
    if not directory.is_dir():
        raise KeyError(f'Terraform directory does not exist: {directory}')
    private = directory / 'key'
    public = directory / 'key.pub'
    if private.is_symlink() or public.is_symlink():
        raise KeyError('Refusing symbolic links for terraform-infra/key or key.pub.')

    desired_parts = None
    temporary_private = None
    if encoded:
        raw = decode_secret(encoded)
        handle, temporary_private = tempfile.mkstemp(prefix='.key.portable.', dir=directory)
        try:
            os.fchmod(handle, 0o600)
            with os.fdopen(handle, 'wb') as stream:
                stream.write(raw)
                stream.flush()
                os.fsync(stream.fileno())
            desired_parts = public_parts(temporary_private)
        except Exception:
            try:
                os.close(handle)
            except OSError:
                pass
            Path(temporary_private).unlink(missing_ok=True)
            raise

    try:
        if public.exists() and desired_parts and read_public(public) != desired_parts:
            raise KeyError('Existing terraform-infra/key.pub differs from the portable credentials key; refusing to overwrite it.')
        if private.exists():
            # OpenSSH rejects private keys with overly broad permissions before
            # it can derive their public identity.
            os.chmod(private, 0o600)
            existing_parts = public_parts(private)
            if desired_parts and existing_parts != desired_parts:
                raise KeyError('Existing terraform-infra/key differs from the portable credentials key; refusing to overwrite it.')
            selected_parts = existing_parts
        elif desired_parts:
            os.replace(temporary_private, private)
            temporary_private = None
            selected_parts = desired_parts
            print('Restored terraform-infra/key from portable credentials.')
        else:
            raise KeyError('Missing terraform-infra/key and TPCS_SSH_PRIVATE_KEY_B64 in credentials-setup.sh.')

        if public.exists():
            if read_public(public) != selected_parts:
                raise KeyError('Existing terraform-infra/key.pub does not match the private key; refusing to overwrite it.')
            os.chmod(public, 0o644)
        else:
            rendered = f'{selected_parts[0]} {selected_parts[1]} tpcs-workstations-portable\n'.encode()
            write_atomic(public, rendered, 0o644)
            print('Rebuilt terraform-infra/key.pub from the private key.')
    finally:
        if temporary_private:
            Path(temporary_private).unlink(missing_ok=True)


def main():
    if len(sys.argv) != 2:
        print('Usage: tpcs_ssh_key.py TERRAFORM_INFRA_DIR', file=sys.stderr)
        return 2
    try:
        # Remove the compatibility environment value before invoking ssh-keygen.
        # The repository loader normally supplies the value only over stdin.
        fallback = os.environ.pop('TPCS_SSH_PRIVATE_KEY_B64', '')
        encoded = sys.stdin.read() or fallback
        materialize(sys.argv[1], encoded)
    except KeyError as exc:
        print(f'TP SSH key setup failed: {exc}', file=sys.stderr)
        return 1
    except OSError:
        print('TP SSH key setup failed: filesystem operation failed.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
