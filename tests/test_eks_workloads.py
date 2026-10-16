import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'roles/access_docs/files'))
import eks_workload_exporter as exporter


class FakeAPI:
    def items(self, path):
        return {
            '/api/v1/pods': [{'status': {'phase': 'Running'}}, {'status': {'phase': 'Pending'}}, {'status': {'phase': 'Succeeded'}}],
            '/api/v1/persistentvolumes': [
                {'metadata': {'name': 'pv'}, 'spec': {'csi': {'driver': 'ebs.csi.aws.com', 'volumeHandle': 'vol-1'}, 'persistentVolumeReclaimPolicy': 'Retain'}, 'status': {'phase': 'Bound'}},
                {'spec': {'hostPath': {}}}],
            '/apis/storage.k8s.io/v1/volumeattachments': [{'status': {'attached': True}}, {'status': {'attached': False}}],
            '/api/v1/services': [{'metadata': {'name': 'lb', 'namespace': 'app'}, 'spec': {'type': 'LoadBalancer'}}, {'spec': {'type': 'ClusterIP'}}],
            '/api/v1/nodes': [{'metadata': {'name': 'node', 'labels': {'eks.amazonaws.com/nodegroup': 'ng'}}, 'spec': {'providerID': 'aws:///eu-west-3a/i-1'}}],
        }[path]

    def get(self, path):
        return {'node': {'memory': {'workingSetBytes': 25, 'availableBytes': 75, 'time': '2026-09-17T07:00:00Z'}}}


class WorkloadTests(unittest.TestCase):
    def test_counts_include_real_zero_and_exclude_non_csi(self):
        lines = []
        exporter.workloads(FakeAPI(), {'region': 'r', 'cluster': 'c'}, lines)
        result = '\n'.join(lines)
        for name in ('pods_running', 'csi_volumes', 'csi_volumes_bound', 'csi_volume_attachments', 'loadbalancer_services'):
            self.assertIn(f'aws_eks_{name}{{region="r",cluster="c"}} 1', result)
        self.assertIn('phase="Failed"} 0', result)
        self.assertIn('reclaim_policy="Retain"', result)

    def test_memory_working_set_percent_and_instance_mapping(self):
        lines = []
        exporter.memory(FakeAPI(), {'region': 'r', 'cluster': 'c'}, lines)
        result = '\n'.join(lines)
        self.assertIn('aws_eks_node_memory_percent{region="r",cluster="c",node="node",instance_id="i-1",nodegroup="ng"} 25.0', result)
        self.assertIn('aws_eks_node_memory_timestamp_seconds{', result)

    def test_memory_failure_does_not_publish_zero(self):
        api = FakeAPI()
        with patch.object(api, 'get', side_effect=OSError('unreachable')):
            lines = []
            exporter.memory(api, {'cluster': 'c'}, lines)
        self.assertNotIn('aws_eks_node_memory_percent{', '\n'.join(lines))
        self.assertIn('stage="memory_node"} 0', '\n'.join(lines))

    def test_tag_attribution_and_unknown(self):
        self.assertEqual(exporter.tagged_cluster([{'Key': 'kubernetes.io/cluster/deleted', 'Value': 'owned'}]), 'deleted')
        self.assertEqual(exporter.tagged_cluster([{'Key': 'ebs.csi.aws.com/cluster', 'Value': 'true'}]), 'unknown')
        self.assertEqual(exporter.tagged_cluster([{'Key': 'elbv2.k8s.aws/cluster', 'Value': 'test'}]), 'test')
        self.assertIsNone(exporter.tagged_cluster([{'Key': 'Name', 'Value': 'personal-disk'}]))

    def test_resources_survive_cluster_deletion_and_show_candidates(self):
        rows = [('vol-1', [{'Key': 'ebs.csi.aws.com/cluster-name', 'Value': 'deleted'}], 'available', 'detached'),
                ('vol-2', [{'Key': 'CSIVolumeName', 'Value': 'pvc'}], 'in-use', ''),
                ('vol-3', [], 'available', 'detached')]
        lines = []
        with patch.object(exporter, 'RESOURCE_KINDS', ('volume',)), patch.object(exporter, 'resource_rows', return_value=rows):
            exporter.resources('r', [], lines)
        text = '\n'.join(lines)
        self.assertIn('cluster_exists="false",review_reason="cluster_missing"', text)
        self.assertIn('cluster_exists="unknown",review_reason="cluster_unknown"', text)
        self.assertIn('aws_eks_regional_resources{region="r",kind="volume"} 2', text)
        self.assertNotIn('vol-3', text)

    def test_empty_resources_publish_zero(self):
        lines = []
        with patch.object(exporter, 'RESOURCE_KINDS', ('volume',)), patch.object(exporter, 'resource_rows', return_value=[]):
            exporter.resources('r', [], lines)
        self.assertIn('aws_eks_regional_resources{region="r",kind="volume"} 0', lines)

    def test_failed_discovery_never_marks_resources_orphaned(self):
        with patch.object(exporter, 'aws', side_effect=OSError('denied')), patch.object(exporter, 'resources') as scan:
            text = exporter.collect(['r'], 'resources')
        scan.assert_not_called()
        self.assertIn('stage="discovery"} 0', text)

    def test_failed_inventory_is_not_false_zero(self):
        lines = []
        with patch.object(exporter, 'RESOURCE_KINDS', ('volume',)), patch.object(exporter, 'resource_rows', side_effect=subprocess.CalledProcessError(1, 'aws')):
            exporter.resources('r', ['c'], lines)
        self.assertNotIn('aws_eks_regional_resources{', '\n'.join(lines))
        self.assertIn('stage="volume"} 0', '\n'.join(lines))

    def test_kubernetes_list_pagination(self):
        api = object.__new__(exporter.Kubernetes)
        with patch.object(api, 'get', side_effect=[{'items': [1], 'metadata': {'continue': 'a/b'}}, {'items': [2], 'metadata': {}}]) as get:
            self.assertEqual(api.items('/api/v1/pods'), [1, 2])
        self.assertIn('continue=a%2Fb', get.call_args.args[0])


if __name__ == '__main__':
    unittest.main()
