"""Test real APT candidate selection using a temporary, local-only repository."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml
from jinja2 import Environment

ROOT = Path(__file__).resolve().parents[1]
OVERLAY = ROOT / 'versions/baselines/tpiac-2026-09-29/tpcs-iac-overlay'

class AptConstraintsTest(unittest.TestCase):
    def test_real_apt_candidates(self):
        cases = [
            (ROOT/'versions/tasks/baseline.yml', 'tpcs_apt_constraints',
             json.loads((ROOT/'versions/apt-constraints.json').read_text())['student'],
             {'ansible-core': ['2.17.14-1', '2.17.15-1', '2.18.1-1'],
              'xrdp': ['0.9.17-2ubuntu3.1', '0.9.18-1', '0.10.1-1'],
              'libxpm4': ['1:3.5.12-1ubuntu0.22.04.4']},
             {'ansible-core': '2.17.15-1', 'xrdp': '0.9.18-1', 'libxpm4': '1:3.5.12-1ubuntu0.22.04.4'}),
            (OVERLAY/'demoboard/ansible/versions/apt.yml', 'demoboard_apt_constraints',
             json.loads((OVERLAY/'demoboard/ansible/versions/apt-constraints.json').read_text()),
             {'redis-server': ['5:7.0.15-1ubuntu0.24.04.5', '5:7.0.16-1', '5:7.2.1-1'],
              'redis-tools': ['5:7.0.16-1', '5:7.2.1-1'],
              'nodejs': ['22.23.4-1', '24.1.0-1'],
              'postgresql-16': ['16.16-1'], 'postgresql': ['16+257', '17+260'],
              'nginx': ['1.26.0-1']},
             {'redis-server': '5:7.0.16-1', 'redis-tools': '5:7.0.16-1',
              'nodejs': '22.23.4-1', 'postgresql-16': '16.16-1', 'postgresql': '16+257', 'nginx': '(none)'})]
        for task, variable, constraints, versions, expected in cases:
            with self.subTest(task=task), tempfile.TemporaryDirectory() as tmp:
                p = Path(tmp); p.chmod(0o755)
                (p/'lists/partial').mkdir(parents=True)
                (p/'cache/archives/partial').mkdir(parents=True)
                (p/'parts').mkdir()
                (p/'status').write_text('')
                (p/'sources.list').write_text(f'deb [trusted=yes] file:{p} ./\n')
                packages = ''.join(f'Package: {name}\nVersion: {v}\nArchitecture: amd64\nMaintainer: Test <test@example.org>\nDescription: fixture\nFilename: unused.deb\nSize: 1\n\n'
                                   for name, vs in versions.items() for v in vs)
                (p/'Packages').write_text(packages)
                tasks = yaml.safe_load(task.read_text())
                template = next(t['ansible.builtin.copy']['content'] for t in tasks if 'ansible.builtin.copy' in t)
                (p/'preferences').write_text(Environment().from_string(template).render(**{variable: constraints}))
                opts = ['-o', f'Dir::Etc::sourcelist={p}/sources.list', '-o', f'Dir::Etc::sourceparts={p}/parts',
                        '-o', f'Dir::Etc::preferences={p}/preferences', '-o', f'Dir::Etc::preferencesparts={p}/parts',
                        '-o', f'Dir::State::lists={p}/lists', '-o', f'Dir::State::status={p}/status',
                        '-o', f'Dir::Cache={p}/cache', '-o', 'APT::Sandbox::User='+__import__('getpass').getuser()]
                subprocess.run(['apt-get', *opts, 'update'], check=True, capture_output=True)
                for name, version in expected.items():
                    out = subprocess.check_output(['apt-cache', *opts, 'policy', name], text=True, env=dict(os.environ, LC_ALL='C'))
                    self.assertIn('Candidate: '+version, out)

    def test_installed_branch_guard(self):
        import shutil
        executable = shutil.which('ansible-playbook')
        if not executable:
            self.skipTest('ansible-playbook required')
        tasks = yaml.safe_load((OVERLAY/'demoboard/ansible/versions/apt.yml').read_text())
        guard = next(t for t in tasks if t['name'].startswith('Refuse installed'))
        for version, success in [('5:7.0.16-1', True), ('5:7.2.0-1', False)]:
            with self.subTest(version=version), tempfile.TemporaryDirectory() as tmp:
                p = Path(tmp)
                play = [{'hosts': 'localhost', 'gather_facts': False, 'vars': {
                    'demoboard_apt_constraints': {'redis-server': '5:7.0.*', 'nodejs': '22.*'},
                    'ansible_facts': {'packages': {'redis-server': [{'version': version}]}}},
                    'tasks': [guard]}]
                (p/'play.yml').write_text(yaml.safe_dump(play))
                (p/'ansible.cfg').write_text('[defaults]\n')
                result = subprocess.run([executable, '-i', 'localhost,', str(p/'play.yml')],
                    env=dict(os.environ, ANSIBLE_CONFIG=str(p/'ansible.cfg')), capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)

if __name__ == '__main__':
    unittest.main()
