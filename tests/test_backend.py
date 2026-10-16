import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('backend', Path(__file__).parents[1] / 'scripts/tpcs_backend.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)
ENV = {'GITLAB_TFSTATE_URL': 'https://gitlab.example', 'GITLAB_TFSTATE_PROJECT_ID': '5',
       'TF_HTTP_USERNAME': 'test-bot', 'TF_HTTP_PASSWORD': 'fixture'}


class BackendTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'terraform-infra').mkdir()

    def context(self, account='111111111111', env=None):
        with patch.object(backend, 'account_identity', return_value=account):
            return backend.Context(self.root, ENV if env is None else env)

    def test_accounts_are_isolated_and_keys_can_rotate(self):
        first = self.context()
        second = self.context('222222222222')
        rotated = self.context(env=dict(ENV, AWS_ACCESS_KEY_ID='new-key'))
        self.assertNotEqual(first.address, second.address)
        self.assertNotEqual(first.data, second.data)
        self.assertNotEqual(first.plans, second.plans)
        self.assertEqual(first.address, rotated.address)

    def test_inherited_backend_is_replaced(self):
        ctx = self.context(env=dict(ENV, TF_HTTP_ADDRESS='https://wrong.example',
                                    TF_DATA_DIR='/wrong', TF_HTTP_LOCK_METHOD='LOCK',
                                    GITLAB_TFSTATE_BACKUP_AGE_IDENTITY='fixture-not-for-terraform'))
        self.assertEqual(ctx.env['TF_HTTP_ADDRESS'], ctx.address)
        self.assertEqual(ctx.env['TF_HTTP_LOCK_METHOD'], 'POST')
        self.assertEqual(ctx.env['TF_VAR_tpcs_aws_account_id'], ctx.account)
        self.assertEqual(ctx.env['TF_DATA_DIR'], str(ctx.data))
        self.assertNotIn('GITLAB_TFSTATE_BACKUP_AGE_IDENTITY', ctx.env)

    def test_local_state_never_silently_ignored(self):
        (self.root / 'terraform-infra/terraform.tfstate').write_text('{}')
        with self.assertRaises(backend.BackendError):
            self.context()

    def test_untrusted_plan_from_another_account_is_rejected(self):
        import hashlib
        first = self.context()
        second = self.context('222222222222')
        path = second.plan_path('copied.tfplan')
        path.write_bytes(b'plan')
        Path(str(path) + '.json').write_text(json.dumps(dict(first.binding, sha256=hashlib.sha256(b'plan').hexdigest())))
        with self.assertRaises(backend.BackendError):
            second.checked_plan('copied.tfplan')

    def test_plan_path_cannot_escape_account(self):
        with self.assertRaises(backend.BackendError):
            self.context().plan_path('../other.tfplan')

    def test_cli_bypasses_rejected(self):
        for args in [['-lock=false'], ['--lock=false'], ['-state=old.tfstate'], ['saved.tfplan']]:
            with self.assertRaises(backend.BackendError):
                backend.operation_options(args)
        self.assertEqual(backend.operation_options(['-target=aws_instance.vm', '-var', 'n=1']),
                         ['-target=aws_instance.vm', '-var', 'n=1'])

    def test_invalid_credentials_rejected(self):
        for env in [dict(ENV, TF_HTTP_PASSWORD=''), dict(ENV, GITLAB_TFSTATE_URL='http://gitlab.example'),
                    dict(ENV, TF_CLI_ARGS='-lock=false'), dict(ENV, TF_WORKSPACE='another')]:
            with self.assertRaises(backend.BackendError):
                self.context(env=env)

    def test_sts_failure_and_wrong_expected_account(self):
        import subprocess
        with patch.object(backend.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'aws')):
            with self.assertRaises(backend.BackendError):
                backend.account_identity(ENV)
        with patch.object(backend.subprocess, 'run') as mock:
            mock.return_value.stdout = b'{"Account":"111111111111"}'
            with self.assertRaises(backend.BackendError):
                backend.account_identity(dict(ENV, TPCS_EXPECTED_AWS_ACCOUNT_ID='222222222222'))

    def test_existing_migration_destination_refused(self):
        ctx = self.context()
        local = self.root / 'old.tfstate'
        local.write_text(json.dumps({'version': 4, 'serial': 1, 'lineage': 'fixture', 'resources': []}))
        with patch.object(ctx, 'remote', return_value={'serial': 8}):
            with self.assertRaises(backend.BackendError):
                backend.migrate(ctx, [str(local), '--account', ctx.account])
        self.assertTrue(local.exists())

    def test_migration_race_never_overwrites_new_state(self):
        ctx = self.context()
        local = self.root / 'old.tfstate'
        local.write_text(json.dumps({'version': 4, 'serial': 1, 'lineage': 'fixture', 'resources': []}))
        with patch.object(ctx, 'remote', side_effect=[None, {'serial': 9}]), \
             patch.object(ctx, 'write_request') as write:
            with self.assertRaises(backend.BackendError):
                backend.migrate(ctx, [str(local), '--account', ctx.account])
        self.assertEqual([c.args[1] for c in write.call_args_list], ['POST', 'DELETE'])
        self.assertTrue(all(c.args[0] == '/lock' for c in write.call_args_list))
        self.assertTrue(local.exists())


if __name__ == '__main__':
    unittest.main()
