#!/usr/bin/env python3
"""Account-aware Terraform entry point. Credentials must already be exported."""
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import uuid
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import Request, build_opener, HTTPRedirectHandler

ROOT = Path(__file__).resolve().parents[1]
HELP = """Usage: ./tf.sh COMMAND [OPTIONS]
  context                Verify AWS/GitLab identity and show the selected state
  init [-upgrade]        Initialize the selected account (never migrate implicitly)
  plan [OPTIONS]         Save a plan in the selected account's private directory
                         Optional -out=NAME (basename only; default plan.tfplan)
  apply [OPTIONS]        Plan and apply interactively (or with -auto-approve)
  apply-plan [NAME]      Apply a saved plan verified for this account/backend
  show-plan [NAME]       Show a saved plan verified for this account/backend
  destroy [OPTIONS]     Terraform destroy only; use 02-destroy_platform.sh for EKS cleanup
  output [OPTIONS]       Read outputs from the selected backend
  state list|pull        Read the selected state
  validate              Validate Terraform configuration
  migrate-local FILE --account ACCOUNT_ID
                        Explicit local state transfer to an ABSENT remote state

AWS account comes from STS, never from the access key string. State names are
tpcs-workstations-<AWS_ACCOUNT_ID>. One platform per account, shared across PCs.
Credentials: terraform-infra/credentials-setup.sh, or CREDENTIALS_FILE.
See BACKEND.md for switching accounts, migration and recovery credentials.
"""


class BackendError(Exception):
    pass


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def account_identity(env):
    lookup_env = dict(env, AWS_PAGER='', AWS_MAX_ATTEMPTS='2', AWS_EC2_METADATA_DISABLED='true')
    # Endpoints must be AWS's real STS endpoint, not an inherited test override.
    if any(k.startswith('AWS_ENDPOINT_URL') and v for k, v in env.items()):
        raise BackendError('Remove AWS_ENDPOINT_URL overrides before selecting the account.')
    try:
        result = subprocess.run(['aws', 'sts', 'get-caller-identity', '--output', 'json',
                                 '--no-cli-pager', '--cli-connect-timeout', '10',
                                 '--cli-read-timeout', '15'], env=lookup_env,
                                capture_output=True, timeout=40, check=True)
        account = json.loads(result.stdout)['Account']
    except (subprocess.SubprocessError, OSError, KeyError, ValueError):
        raise BackendError('AWS identity check failed. Check credentials/profile/session expiry.') from None
    if not re.fullmatch(r'[0-9]{12}', account):
        raise BackendError('STS did not return a valid AWS account ID.')
    expected = env.get('TPCS_EXPECTED_AWS_ACCOUNT_ID')
    if expected and expected != account:
        raise BackendError('AWS account differs from TPCS_EXPECTED_AWS_ACCOUNT_ID; operation stopped.')
    return account


class Context:
    def __init__(self, root=ROOT, environ=None, allow_local=False):
        self.root = Path(root).resolve()
        self.tfdir = self.root / 'terraform-infra'
        self.env = dict(os.environ if environ is None else environ)
        for name in ['GITLAB_TFSTATE_URL', 'GITLAB_TFSTATE_PROJECT_ID', 'TF_HTTP_USERNAME', 'TF_HTTP_PASSWORD']:
            if not self.env.get(name):
                raise BackendError(f'Missing exported credential variable: {name}')
        self.url = self.env['GITLAB_TFSTATE_URL'].rstrip('/')
        parsed = urlsplit(self.url)
        if parsed.scheme != 'https' or not parsed.netloc or parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise BackendError('GITLAB_TFSTATE_URL must be an HTTPS base URL without credentials/query/fragment.')
        self.project = self.env['GITLAB_TFSTATE_PROJECT_ID']
        if not re.fullmatch(r'[1-9][0-9]*', self.project):
            raise BackendError('GITLAB_TFSTATE_PROJECT_ID must be a numeric project ID.')
        if any(k.startswith('TF_CLI_ARGS') and v for k, v in self.env.items()):
            raise BackendError('Remove TF_CLI_ARGS overrides; pass options explicitly to tf.sh.')
        if self.env.get('TF_WORKSPACE', 'default') != 'default':
            raise BackendError('Use accounts, not Terraform workspaces, with this HTTP backend.')
        if not allow_local and (self.tfdir / 'terraform.tfstate').exists():
            raise BackendError('Local terraform.tfstate found. Use migrate-local explicitly; no empty backend will be selected.')
        self.account = account_identity(self.env)
        self.name = f'tpcs-workstations-{self.account}'
        self.address = f'{self.url}/api/v4/projects/{self.project}/terraform/state/{self.name}'
        backend_id = hashlib.sha256(f'{self.url}/{self.project}'.encode()).hexdigest()[:16]
        self.home = self.tfdir / '.tpcs' / backend_id / self.account
        self.data = self.home / 'data'
        self.plans = self.home / 'plans'
        self.exports = {
            'TF_HTTP_ADDRESS': self.address, 'TF_HTTP_LOCK_ADDRESS': self.address + '/lock',
            'TF_HTTP_UNLOCK_ADDRESS': self.address + '/lock', 'TF_HTTP_LOCK_METHOD': 'POST',
            'TF_HTTP_UNLOCK_METHOD': 'DELETE', 'TF_HTTP_UPDATE_METHOD': 'POST',
            'TF_HTTP_RETRY_MAX': '2', 'TF_HTTP_RETRY_WAIT_MIN': '1', 'TF_HTTP_RETRY_WAIT_MAX': '5',
            'TF_DATA_DIR': str(self.data), 'TF_WORKSPACE': 'default',
            'TF_VAR_tpcs_aws_account_id': self.account,
            'TPCS_AWS_ACCOUNT_ID': self.account, 'TPCS_TF_STATE_NAME': self.name,
        }
        # Remove inherited HTTP options (including client keys); keep only credentials.
        for name in list(self.env):
            if name.startswith('TF_HTTP_') and name not in ['TF_HTTP_USERNAME', 'TF_HTTP_PASSWORD']:
                del self.env[name]
        self.env.update(self.exports)
        self.env.pop('GITLAB_TFSTATE_BACKUP_AGE_IDENTITY', None)
        for path in [self.data, self.plans]:
            path.mkdir(parents=True, exist_ok=True, mode=0o700)

    @property
    def binding(self):
        return {'account': self.account, 'address': self.address}

    def remote(self):
        import base64
        auth = base64.b64encode(f"{self.env['TF_HTTP_USERNAME']}:{self.env['TF_HTTP_PASSWORD']}".encode()).decode()
        request = Request(self.address, headers={'Authorization': 'Basic ' + auth})
        try:
            with build_opener(NoRedirect).open(request, timeout=20) as response:
                if response.status == 204:
                    return {}  # Existing lock-only state is not an absent destination.
                return json.load(response)
        except HTTPError as exc:
            if exc.code == 404:
                # Distinguish absent state from inaccessible/nonexistent project.
                # The Projects API uses PRIVATE-TOKEN authentication.
                check = Request(f'{self.url}/api/v4/projects/{self.project}',
                                headers={'PRIVATE-TOKEN': self.env['TF_HTTP_PASSWORD']})
                with build_opener(NoRedirect).open(check, timeout=20) as response:
                    project = json.load(response)
                    if str(project['id']) != self.project:
                        raise BackendError('Wrong GitLab project returned.')
                return None
            raise BackendError(f'GitLab backend access failed (HTTP {exc.code}).') from None

    def write_request(self, suffix, method, payload):
        import base64
        auth = base64.b64encode(f"{self.env['TF_HTTP_USERNAME']}:{self.env['TF_HTTP_PASSWORD']}".encode()).decode()
        req = Request(self.address + suffix, method=method, data=json.dumps(payload).encode(),
                      headers={'Authorization': 'Basic ' + auth, 'Content-Type': 'application/json'})
        try:
            with build_opener(NoRedirect).open(req, timeout=30) as response:
                if response.status != 200:
                    raise BackendError('Unexpected response during state migration.')
        except HTTPError as exc:
            raise BackendError(f'State migration request refused (HTTP {exc.code}).') from None

    @contextmanager
    def lock(self, path):
        with path.open('a') as handle:
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise BackendError('Another local Terraform operation is running; retry when it finishes.') from None
            yield

    def terraform(self, args, capture=False):
        return subprocess.run(['terraform', *args], cwd=self.tfdir, env=self.env,
                              stdout=subprocess.PIPE if capture else None, check=False)

    def init(self, upgrade=False):
        self.remote()  # Reject an inaccessible project instead of treating its 404 as an empty state.
        # Provider lockfile is common to the source tree, so serialize init across accounts.
        with self.lock(self.tfdir / '.tpcs' / 'init.lock'):
            args = ['terraform', 'init', '-reconfigure', '-input=false', '-no-color']
            if upgrade:
                args.append('-upgrade')
            result = subprocess.run(args, cwd=self.tfdir, env=self.env,
                                    stdout=sys.stderr, check=False)
            if result.returncode:
                raise BackendError('Terraform backend initialization failed.')

    def plan_path(self, name):
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', name):
            raise BackendError('Plan name must be a basename, without directory components.')
        return self.plans / name

    def checked_plan(self, name):
        plan = self.plan_path(name)
        try:
            metadata = json.loads(Path(str(plan) + '.json').read_text())
            digest = hashlib.sha256(plan.read_bytes()).hexdigest()
        except (OSError, ValueError):
            raise BackendError('No verified saved plan for this account. Run tf.sh plan first.') from None
        if metadata != dict(self.binding, sha256=digest):
            raise BackendError('Plan account/backend or content mismatch; regenerate the plan.')
        return plan


def operation_options(args):
    """Reject backend/lock bypasses and saved-plan paths on direct apply/destroy."""
    takes_value = {'-var', '-var-file', '-target', '-replace', '-parallelism', '-lock-timeout'}
    result = []
    expect_value = False
    for arg in args:
        if expect_value:
            result.append(arg)
            expect_value = False
            continue
        key = '-' + arg.split('=', 1)[0].lstrip('-')
        if not arg.startswith('-'):
            raise BackendError('Positional plan files are refused; use apply-plan NAME.')
        if key in ['-state', '-state-out', '-backup', '-out', '-chdir', '-backend-config', '-lock']:
            raise BackendError(f'Option {key} is managed by the account helper.')
        result.append(arg)
        expect_value = arg in takes_value
    if expect_value:
        raise BackendError('Missing Terraform option value.')
    return result


def migrate(context, args):
    if len(args) != 3 or args[1] != '--account' or args[2] != context.account:
        raise BackendError('Use migrate-local FILE --account <verified AWS account ID>.')
    source = Path(args[0]).resolve()
    raw = source.read_bytes()
    state = json.loads(raw)
    if state.get('version') != 4 or not state.get('lineage') or not isinstance(state.get('serial'), int) or not isinstance(state.get('resources'), list):
        raise BackendError('Unsupported local Terraform state format.')
    if context.remote() is not None:
        raise BackendError('Migration target already exists. Refusing to overwrite it.')
    recovery = context.home / 'recovery'
    recovery.mkdir(mode=0o700, exist_ok=True)
    digest = hashlib.sha256(raw).hexdigest()
    backup = recovery / f'{digest}.tfstate'
    backup.write_bytes(raw)
    # Hold the GitLab lock across the final absence check and write. This also
    # prevents a different controller creating a state between check and upload.
    from datetime import datetime, timezone
    lock_id = str(uuid.uuid4())
    lock = {'ID': lock_id, 'Operation': 'OperationTypeApply', 'Info': 'local state migration',
            'Who': 'tpcs-migrate-local', 'Version': '1.11.4', 'Path': context.name,
            'Created': datetime.now(timezone.utc).isoformat()}
    context.write_request('/lock', 'POST', lock)
    try:
        if context.remote() != {}:
            raise BackendError('A state appeared during migration; refusing to overwrite it.')
        context.write_request('?ID=' + lock_id, 'POST', state)
    finally:
        context.write_request('/lock', 'DELETE', {'ID': lock_id})
    context.init()
    fetched = context.terraform(['state', 'pull'], capture=True)
    restored = json.loads(fetched.stdout) if fetched.returncode == 0 else None
    # Terraform may update its own version metadata on push, but not the resources.
    if restored is None or any(restored.get(k) != state.get(k) for k in ['lineage', 'serial', 'resources', 'outputs']):
        raise BackendError('Migration verification failed; keep both states and investigate before apply.')
    if source == context.tfdir / 'terraform.tfstate':
        if source.read_bytes() != raw:
            raise BackendError('Local state changed during migration; stop the old controller.')
        source.rename(recovery / f'{digest}-original.tfstate')
    print(f'Migration verified. Local recovery copy: {backup}')
    return 0


def run(argv, root=ROOT, environ=None):
    if not argv or argv[0] in ['help', '--help', '-h']:
        print(HELP)
        return 0
    os.umask(0o077)
    command, *args = argv
    allowed = {'context', 'env', 'init', 'plan', 'apply', 'apply-plan', 'show-plan',
               'destroy', 'output', 'state', 'validate', 'migrate-local'}
    if command not in allowed:
        raise BackendError('Unsupported command. Run ./tf.sh help.')
    context = Context(root, environ, allow_local=command == 'migrate-local')
    for arg in args:
        if '-' + arg.split('=', 1)[0].lstrip('-') in ['-state', '-state-out', '-backup', '-chdir', '-backend-config', '-lock']:
            raise BackendError('Backend/state/lock overrides are not accepted by this helper.')
    if command == 'env':
        for key, value in context.exports.items():
            print(f'export {key}={shlex.quote(value)}')
        return 0
    if command == 'context':
        remote = context.remote()
        print(json.dumps(dict(context.binding, state=context.name, data_dir=str(context.data),
                              remote_state='absent' if remote is None else 'present'), indent=2))
        return 0
    with context.lock(context.home / 'operation.lock'):
        if command == 'migrate-local':
            return migrate(context, args)
        if command == 'init':
            if args not in [[], ['-upgrade']]:
                raise BackendError('Only init [-upgrade] is supported. Use migrate-local for migration.')
            context.init(upgrade=bool(args))
            return 0
        # Every invocation rebinds the backend before reading outputs or changing resources.
        context.init()
        if command in ['apply-plan', 'show-plan']:
            if len(args) > 1:
                raise BackendError('Specify at most one saved plan basename.')
            path = context.checked_plan(args[0] if args else 'plan.tfplan')
            return context.terraform(['apply' if command == 'apply-plan' else 'show', str(path)]).returncode
        if command == 'plan':
            name = 'plan.tfplan'
            options = []
            for arg in args:
                if arg.startswith('-out='):
                    name = arg.split('=', 1)[1]
                else:
                    options.append(arg)
            path = context.plan_path(name)
            metadata = Path(str(path) + '.json')
            metadata.unlink(missing_ok=True)
            result = context.terraform(['plan', *operation_options(options),
                                        '-var=tpcs_aws_account_id=' + context.account, '-out=' + str(path)])
            if result.returncode in [0, 2] and path.exists():
                metadata.write_text(json.dumps(dict(context.binding, sha256=hashlib.sha256(path.read_bytes()).hexdigest())))
            return result.returncode
        if command in ['apply', 'destroy']:
            args = [*operation_options(args), '-var=tpcs_aws_account_id=' + context.account]
        elif command == 'state' and (not args or args[0] not in ['list', 'pull']):
            raise BackendError('Only state list/pull are supported. Migration uses migrate-local.')
        elif command == 'validate' and args:
            raise BackendError('validate takes no options in this helper.')
        return context.terraform([command, *args]).returncode


def main():
    try:
        return run(sys.argv[1:])
    except BackendError as exc:
        print(f'Backend: {exc}', file=sys.stderr)
        return 1
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        # Network/parse exceptions can include response data: do not echo secrets.
        print(f'Backend operation failed ({type(exc).__name__}). Check connectivity and configuration.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
