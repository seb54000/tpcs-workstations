"""Offline checks for the shared TP selection used before apply/destroy."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class TpNamesTest(unittest.TestCase):
    def validate(self, value):
        env = dict(os.environ, TF_VAR_tp_names=value, TF_VAR_tp_name='tpiac')
        return subprocess.run(
            ['bash', '-c', 'source "$1"; tpcs_validate_tp_names',
             'test', str(ROOT / 'scripts/tpcs-tp-names.sh')],
            env=env, capture_output=True, text=True,
        ).returncode

    def test_valid_lists(self):
        for value in ['["tpiac"]', '["tpkube"]', '["tpmon"]',
                      '["tpmon", "tpiac", "tpkube"]']:
            with self.subTest(value=value):
                self.assertEqual(self.validate(value), 0)

    def test_invalid_or_missing_lists_ignore_legacy_variable(self):
        for value in ['', '[]', 'null', '{}', '"tpiac"', '[1]',
                      '["unknown"]', '["tpiac", null]', '[',
                      '["tpiac"]\n["tpmon"]']:
            with self.subTest(value=value):
                self.assertNotEqual(self.validate(value), 0)

    def test_destroy_uses_only_list(self):
        script = (ROOT / '02-destroy_platform.sh').read_text()
        function = script.split('tp_iac_is_enabled() {', 1)[1].split('\n}', 1)[0]
        for value, expected in [('["tpmon"]', 1), ('["tpmon", "tpiac"]', 0),
                                ('["tpkube"]', 1), ('["tpiac"]', 0)]:
            with self.subTest(value=value):
                result = subprocess.run(
                    ['bash', '-c', 'tp_iac_is_enabled() {' + function + '\n}; tp_iac_is_enabled'],
                    env=dict(os.environ, TF_VAR_tp_names=value, TF_VAR_tp_name='tpiac'),
                    capture_output=True,
                )
                self.assertEqual(result.returncode, expected)
