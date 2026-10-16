#!/usr/bin/env python3
"""Read-only inventory of GitLab Terraform states; never expose attributes/outputs."""
import argparse
import json
import os
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlsplit
from urllib.request import Request, build_opener, HTTPRedirectHandler

QUERY = '''query($path: ID!, $after: String) {
  project(fullPath: $path) {
    terraformStates(first: 100, after: $after) {
      nodes { name latestVersion { serial } }
      pageInfo { hasNextPage endCursor }
    }
  }
}'''


class InventoryError(Exception):
    pass


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Client:
    def __init__(self, env=None):
        env = os.environ if env is None else env
        self.url = env.get('GITLAB_TFSTATE_URL', '').rstrip('/')
        url = urlsplit(self.url)
        if (url.scheme != 'https' or not url.netloc or url.username or url.password
                or url.query or url.fragment or url.path not in ('', '/')):
            raise InventoryError('GITLAB_TFSTATE_URL must be an HTTPS origin.')
        self.project = env.get('GITLAB_TFSTATE_PROJECT_ID', '')
        if not re.fullmatch(r'[1-9][0-9]*', self.project):
            raise InventoryError('GITLAB_TFSTATE_PROJECT_ID must be a numeric project ID.')
        self.token = env.get('GITLAB_TFSTATE_READ_TOKEN') or env.get('TF_HTTP_PASSWORD')
        if not self.token:
            raise InventoryError('Export GITLAB_TFSTATE_READ_TOKEN (or TF_HTTP_PASSWORD).')
        self.expected_path = env.get('GITLAB_TFSTATE_PROJECT_PATH')
        self.opener = build_opener(NoRedirect)

    def request(self, path, body=None):
        headers = {'PRIVATE-TOKEN': self.token}
        if body is not None:
            headers['Content-Type'] = 'application/json'
        request = Request(self.url + path, headers=headers,
                          data=None if body is None else json.dumps(body).encode())
        try:
            with self.opener.open(request, timeout=20) as response:
                raw = response.read(50 * 1024 * 1024 + 1)
        except HTTPError as exc:
            raise InventoryError(f'GitLab request failed (HTTP {exc.code}); check access/token/project.') from None
        except (URLError, TimeoutError, OSError):
            raise InventoryError('GitLab connection failed; check network and TLS certificate.') from None
        if len(raw) > 50 * 1024 * 1024:
            raise InventoryError('GitLab response exceeds 50 MiB.')
        try:
            return json.loads(raw)
        except ValueError:
            raise InventoryError('GitLab returned invalid JSON.') from None

    def inventory(self, account=None, resources=False):
        project = self.request(f'/api/v4/projects/{self.project}')
        path = project['path_with_namespace']
        if str(project['id']) != self.project or (self.expected_path and path != self.expected_path):
            raise InventoryError('GitLab project ID/path mismatch.')
        entries, seen, cursors = [], set(), set()
        cursor = None
        for _ in range(100):
            result = self.request('/api/graphql', {'query': QUERY, 'variables': {'path': path, 'after': cursor}})
            if result.get('errors') or not result.get('data', {}).get('project'):
                raise InventoryError('Cannot enumerate states (GraphQL access/error).')
            connection = result['data']['project']['terraformStates']
            for node in connection['nodes']:
                name = node['name']
                if name in seen:
                    raise InventoryError('Duplicate state during pagination; retry inventory.')
                seen.add(name)
                if account and name != f'tpcs-workstations-{account}':
                    continue
                entry = summarize(name, None, resources)
                version = node['latestVersion']
                if version is not None:
                    serial = version['serial']
                    if type(serial) is not int or serial < 0:
                        raise InventoryError('Invalid state version serial.')
                    state = self.request(f'/api/v4/projects/{self.project}/terraform/state/{quote(name, safe="")}/versions/{serial}')
                    if state.get('serial') != serial:
                        raise InventoryError('Inconsistent state version; retry inventory.')
                    entry = summarize(name, state, resources)
                entries.append(entry)
            info = connection['pageInfo']
            if not info['hasNextPage']:
                return {'project_id': self.project, 'project_path': path,
                        'states': sorted(entries, key=lambda entry: entry['name'])}
            cursor = info['endCursor']
            if not cursor or cursor in cursors:
                raise InventoryError('Invalid pagination cursor.')
            cursors.add(cursor)
        raise InventoryError('State pagination exceeds 100 pages.')


def summarize(name, state, details=False):
    match = re.fullmatch(r'tpcs-workstations-([0-9]{12})', name)
    entry = {'name': name, 'account': match.group(1) if match else None,
             'serial': None, 'status': 'no-version', 'managed_instances': 0,
             'data_instances': 0}
    if details:
        entry['resources'] = []
    if state is None:
        return entry
    if state.get('version') != 4 or not isinstance(state.get('resources'), list):
        raise InventoryError('Unsupported Terraform state format.')
    entry['serial'] = state['serial']
    for resource in state['resources']:
        mode = resource.get('mode')
        if mode not in ('managed', 'data') or not isinstance(resource.get('instances'), list):
            raise InventoryError('Unsupported resource format.')
        entry[f'{mode}_instances'] += len(resource['instances'])
        if details:
            address = '.'.join(part for part in (resource.get('module'),
                               'data' if mode == 'data' else None,
                               resource['type'], resource['name']) if part)
            entry['resources'].append({'address': address, 'mode': mode,
                                       'instances': len(resource['instances'])})
    entry['status'] = 'resources' if entry['managed_instances'] else 'empty'
    return entry


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--json', action='store_true', help='Machine-readable summary (no attributes/outputs)')
    parser.add_argument('--resources', action='store_true', help='Include resource block addresses and instance counts')
    parser.add_argument('--account', help='Filter by a 12-digit AWS account ID; no AWS request')
    args = parser.parse_args(argv)
    if args.account and not re.fullmatch(r'[0-9]{12}', args.account):
        parser.error('--account must contain 12 digits')
    try:
        report = Client().inventory(args.account, args.resources)
    except InventoryError as exc:
        print(f'State inventory failed: {exc}', file=sys.stderr)
        return 1
    except (KeyError, TypeError, ValueError):
        print('State inventory failed: unexpected GitLab/state format.', file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(f'Project: {report["project_path"]} (ID {report["project_id"]})')
        print('STATE | ACCOUNT | SERIAL | STATUS | MANAGED | DATA')
        for entry in report['states']:
            print(' | '.join(str(entry[key]) if entry[key] is not None else '-'
                             for key in ('name', 'account', 'serial', 'status', 'managed_instances', 'data_instances')))
            for resource in entry.get('resources', []):
                print(f'  {resource["address"]}: {resource["instances"]} instance(s)')
        if not report['states']:
            print('No states found' + (' for this account.' if args.account else '.'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
