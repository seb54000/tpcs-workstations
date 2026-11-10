import base64
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('ssh_key', Path(__file__).parents[1] / 'scripts/tpcs_ssh_key.py')
ssh_key = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ssh_key)


def create_key(directory, name):
    path = Path(directory, name)
    subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(path)], check=True)
    return path


class SshKeyTest(unittest.TestCase):
    def test_restores_private_and_derives_public(self):
        with tempfile.TemporaryDirectory() as source, tempfile.TemporaryDirectory() as target:
            key = create_key(source, 'source')
            encoded = base64.b64encode(key.read_bytes()).decode()
            ssh_key.materialize(target, encoded)
            self.assertEqual(ssh_key.public_parts(Path(target, 'key')), ssh_key.read_public(Path(target, 'key.pub')))
            self.assertEqual(Path(target, 'key').stat().st_mode & 0o777, 0o600)
            self.assertEqual(Path(target, 'key.pub').stat().st_mode & 0o777, 0o644)

    def test_existing_same_key_is_kept_and_permissions_repaired(self):
        with tempfile.TemporaryDirectory() as target:
            key = create_key(target, 'key')
            Path(target, 'key.pub').unlink()
            os.chmod(key, 0o644)
            encoded = base64.b64encode(key.read_bytes()).decode()
            before = key.read_bytes()
            ssh_key.materialize(target, encoded)
            ssh_key.materialize(target, '')
            self.assertEqual(key.read_bytes(), before)
            self.assertEqual(key.stat().st_mode & 0o777, 0o600)

    def test_refuses_different_existing_private_key(self):
        with tempfile.TemporaryDirectory() as source, tempfile.TemporaryDirectory() as target:
            wanted = create_key(source, 'wanted')
            create_key(target, 'key')
            encoded = base64.b64encode(wanted.read_bytes()).decode()
            with self.assertRaisesRegex(ssh_key.KeyError, 'differs'):
                ssh_key.materialize(target, encoded)

    def test_refuses_mismatched_existing_public_key(self):
        with tempfile.TemporaryDirectory() as target, tempfile.TemporaryDirectory() as other:
            create_key(target, 'key')
            other_key = create_key(other, 'other')
            Path(target, 'key.pub').write_text(Path(str(other_key) + '.pub').read_text())
            with self.assertRaisesRegex(ssh_key.KeyError, 'does not match'):
                ssh_key.materialize(target, '')

    def test_missing_or_invalid_portable_key_fails_without_files(self):
        for encoded in ('', 'not base64'):
            with tempfile.TemporaryDirectory() as target:
                with self.assertRaises(ssh_key.KeyError):
                    ssh_key.materialize(target, encoded)
                self.assertFalse(Path(target, 'key').exists())


if __name__ == '__main__':
    unittest.main()
