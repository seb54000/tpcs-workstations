import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('tpcs_states', Path(__file__).resolve().parents[1] / 'scripts/tpcs_states.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
ENV = {'GITLAB_TFSTATE_URL': 'https://gitlab.example.com', 'GITLAB_TFSTATE_PROJECT_ID': '5',
       'GITLAB_TFSTATE_PROJECT_PATH': 'seb/states', 'GITLAB_TFSTATE_READ_TOKEN': 'reader',
       'TF_HTTP_PASSWORD': 'writer'}
PROJECT = {'id': 5, 'path_with_namespace': 'seb/states'}


def page(nodes, more=False, cursor=None):
    return {'data': {'project': {'terraformStates': {'nodes': nodes,
            'pageInfo': {'hasNextPage': more, 'endCursor': cursor}}}}}


def state(resources):
    return {'version': 4, 'serial': 2, 'resources': resources, 'outputs': {'secret': 'NEVER_DISPLAY'}}


class InventoryTests(unittest.TestCase):
    def test_counts_instances_not_blocks_or_data_and_hides_secrets(self):
        payload = state([
            {'mode': 'managed', 'type': 'aws_instance', 'name': 'vm', 'module': 'module.tp',
             'instances': [{'attributes': {'password': 'NEVER_DISPLAY'}}, {'deposed': 'old'}]},
            {'mode': 'managed', 'type': 'aws_vpc', 'name': 'removed', 'instances': []},
            {'mode': 'data', 'type': 'aws_ami', 'name': 'image', 'instances': [{}]}])
        entry = m.summarize('tpcs-workstations-123456789012', payload, True)
        self.assertEqual(entry['managed_instances'], 2)
        self.assertEqual(entry['data_instances'], 1)
        self.assertEqual(entry['status'], 'resources')
        self.assertEqual(entry['resources'][0]['address'], 'module.tp.aws_instance.vm')
        self.assertNotIn('NEVER_DISPLAY', str(entry))
        self.assertEqual(m.summarize('state', state(payload['resources'][1:]))['status'], 'empty')
        self.assertEqual(m.summarize('state', None)['status'], 'no-version')

    def test_pagination_pinned_version_and_encoded_names(self):
        client = m.Client(ENV)
        with patch.object(client, 'request', side_effect=[PROJECT,
                page([{'name': 'a/b', 'latestVersion': {'serial': 2}}], True, 'next'),
                state([]), page([{'name': 'locked', 'latestVersion': None}])]) as request:
            entries = client.inventory()['states']
        self.assertEqual(len(entries), 2)
        self.assertEqual(request.call_args_list[2].args[0], '/api/v4/projects/5/terraform/state/a%2Fb/versions/2')
        self.assertEqual(request.call_args_list[3].args[1]['variables']['after'], 'next')
        self.assertEqual(client.token, 'reader')
        self.assertEqual(m.Client(dict(ENV, GITLAB_TFSTATE_READ_TOKEN='')).token, 'writer')

    def test_filter_skips_other_account_download(self):
        client = m.Client(ENV)
        with patch.object(client, 'request', side_effect=[PROJECT, page([
                {'name': 'tpcs-workstations-111111111111', 'latestVersion': {'serial': 2}},
                {'name': 'tpcs-workstations-222222222222', 'latestVersion': None}])]) as request:
            entries = client.inventory('222222222222')['states']
        self.assertEqual(len(entries), 1)
        self.assertEqual(request.call_count, 2)

    def test_errors_never_look_like_empty_inventory(self):
        for responses in ([PROJECT, {'errors': [{'message': 'secret'}]}],
                          [dict(PROJECT, id=6)],
                          [PROJECT, page([], True, 'same'), page([], True, 'same')],
                          [PROJECT, page([{'name': 'state', 'latestVersion': {'serial': 2}}]), dict(state([]), serial=3)]):
            client = m.Client(ENV)
            with patch.object(client, 'request', side_effect=responses):
                with self.assertRaises(m.InventoryError):
                    client.inventory()

    def test_redirects_and_unsafe_urls(self):
        self.assertIsNone(m.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://other.example'))
        for url in ('http://gitlab.example', 'https://token@gitlab.example', 'https://gitlab.example?token=secret'):
            with self.assertRaises(m.InventoryError):
                m.Client(dict(ENV, GITLAB_TFSTATE_URL=url))


if __name__ == '__main__':
    unittest.main()
