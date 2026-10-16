#!/usr/bin/env python3
"""Manual test: real GitLab + Terraform, simulated AWS identities, no AWS provider.

Source credentials before running. Creates three temporary UUID-derived numeric
account state names only after checking they are absent, then removes them.
"""
import base64
import importlib.util
import json
import os
from pathlib import Path
import secrets
import tempfile
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, build_opener
import uuid

spec = importlib.util.spec_from_file_location('backend', Path(__file__).parents[1] / 'scripts/tpcs_backend.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


def main():
    env = {k: v for k, v in os.environ.items() if k in [
        'PATH', 'HOME', 'GITLAB_TFSTATE_URL', 'GITLAB_TFSTATE_PROJECT_ID',
        'TF_HTTP_USERNAME', 'TF_HTTP_PASSWORD']}
    os.umask(0o077)
    accounts = [str(secrets.randbelow(10**12)).zfill(12) for _ in range(3)]
    created = []
    with tempfile.TemporaryDirectory(prefix='tpcs-backend-integration-') as tmp:
        root = Path(tmp)
        tfdir = root / 'terraform-infra'
        tfdir.mkdir()
        (tfdir / 'main.tf').write_text('''terraform {
  backend "http" {}
}
variable "tpcs_aws_account_id" { type = string }
output "test_account" { value = var.tpcs_aws_account_id }
''')

        def ctx(account, allow_local=False):
            with patch.object(backend, 'account_identity', return_value=account):
                return backend.Context(root, env, allow_local=allow_local)

        def run(account, *args):
            with patch.object(backend, 'account_identity', return_value=account):
                result = backend.run(list(args), root, env)
                assert result == 0, f'Command {args[0]} failed'

        try:
            for account in accounts:
                current = ctx(account)
                assert current.remote() is None, 'Refusing an already-existing state name'
                created.append(current)
            for account in accounts[:2]:
                run(account, 'plan', '-input=false')
                run(account, 'apply-plan')
                assert ctx(account).remote()['outputs']['test_account']['value'] == account
            assert ctx(accounts[0]).data != ctx(accounts[1]).data
            # Switching back must recover exactly the first state and saved plan.
            ctx(accounts[0]).checked_plan('plan.tfplan')
            assert ctx(accounts[0]).remote()['outputs']['test_account']['value'] == accounts[0]
            print('PASS: two independent remote states, account directories and verified plans')

            local = tfdir / 'terraform.tfstate'
            original = {'version': 4, 'terraform_version': '1.11.4', 'serial': 1,
                        'lineage': str(uuid.uuid4()), 'outputs': {}, 'resources': []}
            local.write_text(json.dumps(original))
            run(accounts[2], 'migrate-local', str(local), '--account', accounts[2])
            assert not local.exists()
            restored = ctx(accounts[2]).remote()
            assert restored['lineage'] == original['lineage']
            assert restored['serial'] == original['serial']
            print('PASS: explicit local migration, remote verification and preserved local backup')
        finally:
            for current in created:
                auth = base64.b64encode(f"{env['TF_HTTP_USERNAME']}:{env['TF_HTTP_PASSWORD']}".encode()).decode()
                req = Request(current.address, method='DELETE', headers={'Authorization': 'Basic ' + auth})
                try:
                    with build_opener(backend.NoRedirect).open(req, timeout=20) as response:
                        assert response.status == 200
                except HTTPError as exc:
                    if exc.code != 404:
                        raise
            print('Temporary fixture states deleted; no AWS resources were created')


if __name__ == '__main__':
    main()
