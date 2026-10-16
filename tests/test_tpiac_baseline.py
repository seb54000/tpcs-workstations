"""Exercise exact snap selection and drift refusal without touching a real host."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
FAKE_SNAP = '''#!/usr/bin/env python3
import json, os, pathlib, sys
p = pathlib.Path(os.environ['BASELINE_TEST_DIR'])
a = sys.argv[1:]
s = json.loads((p/'state.json').read_text())
with (p/'calls').open('a') as f: f.write(json.dumps(a)+'\\n')
if a[0] == 'list':
    if not s: sys.exit(1)
    print('Name Version Rev Tracking Publisher Notes')
    print('docker 29.8.0', s['revision'], 'latest/stable canonical', 'held' if s['held'] else '-')
elif a[0] == 'install':
    s = {'revision': a[2].split('=')[1], 'held': False}
elif a[:2] == ['refresh', '--hold=forever']:
    s['held'] = True
else: raise RuntimeError(a)
(p/'state.json').write_text(json.dumps(s))
'''


@unittest.skipUnless(shutil.which('ansible-playbook'), 'ansible-playbook required')
class BaselineSnapTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        (self.path/'snap').write_text(FAKE_SNAP)
        (self.path/'snap').chmod(0o755)
        (self.path/'ansible.cfg').write_text('[defaults]\n')
        self.env = dict(os.environ, BASELINE_TEST_DIR=str(self.path),
                        ANSIBLE_CONFIG=str(self.path/'ansible.cfg'),
                        PATH=str(self.path)+os.pathsep+os.environ['PATH'])
        play = [{'hosts': 'localhost', 'connection': 'local', 'gather_facts': False,
                 'vars': {'ansible_python_interpreter': shutil.which('python3'),
                          'item': {'package': 'docker', 'classic': False},
                          'tpcs_snap_versions': {'docker': {'revision': '3613'}}},
                 'tasks': [{'ansible.builtin.import_tasks': str(ROOT/'versions/tasks/pinned_snap.yml')}]}]
        (self.path/'play.yml').write_text(yaml.safe_dump(play))

    def run_case(self, state):
        (self.path/'state.json').write_text(json.dumps(state))
        (self.path/'calls').write_text('')
        result = subprocess.run(['ansible-playbook', '-i', 'localhost,', str(self.path/'play.yml')],
                                cwd=self.path, env=self.env, text=True, capture_output=True, timeout=40)
        calls = [json.loads(x) for x in (self.path/'calls').read_text().splitlines()]
        return result, calls

    def test_missing_revision_installed_then_held(self):
        r, calls = self.run_case({})
        self.assertEqual(r.returncode, 0, r.stdout+r.stderr)
        self.assertEqual(calls, [['list', 'docker'], ['install', 'docker', '--revision=3613'],
                                 ['refresh', '--hold=forever', 'docker']])

    def test_revision_drift_never_changes_installed_software(self):
        r, calls = self.run_case({'revision': '9999', 'held': False})
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('differs from baseline', r.stdout)
        self.assertEqual(calls, [['list', 'docker']])

    def test_second_run_is_read_only(self):
        r, calls = self.run_case({'revision': '3613', 'held': True})
        self.assertEqual(r.returncode, 0, r.stdout+r.stderr)
        self.assertIn('changed=0', r.stdout)
        self.assertEqual(calls, [['list', 'docker']])


class AptSelectionTest(unittest.TestCase):
    def test_multiarch_and_unknown_package(self):
        spec = importlib.util.spec_from_file_location('tpcs_versions', ROOT/'versions/filter_plugins/tpcs_versions.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(module.pinned_packages(['libtest'], {'libtest:amd64': '1.2-3'}), ['libtest=1.2-3'])
        with self.assertRaisesRegex(Exception, 'absent from TPCS baseline'):
            module.pinned_packages(['not-captured'], {})


if __name__ == '__main__':
    unittest.main()
