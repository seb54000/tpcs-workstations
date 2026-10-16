import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('eks_exporter', ROOT / 'roles/access_docs/files/eks_prom_exporter.py')
exporter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(exporter)


class MonitoringTests(unittest.TestCase):
    def test_empty_region_is_zero(self):
        with patch.object(exporter, 'aws', return_value={'clusters': []}):
            result = exporter.collect(['eu-west-3'])
        self.assertIn('aws_eks_clusters{region="eu-west-3"} 0', result)
        self.assertIn('stage="inventory"} 1', result)

    def test_denied_is_not_zero(self):
        with patch.object(exporter, 'aws', side_effect=subprocess.CalledProcessError(1, 'aws')):
            result = exporter.collect(['eu-west-3'])
        self.assertIn('stage="inventory"} 0', result)
        self.assertNotIn('aws_eks_clusters{', result)

    def fake_aws(self, region, service, operation, **kwargs):
        return {
            'list-clusters': {'clusters': ['training']},
            'describe-cluster': {'cluster': {'status': 'ACTIVE', 'version': '1.34'}},
            'list-nodegroups': {'nodegroups': ['workers']},
            'describe-nodegroup': {'nodegroup': {'status': 'DEGRADED', 'health': {'issues': [{'code': 'test'}]}, 'scalingConfig': {'minSize': 0, 'maxSize': 3, 'desiredSize': 2}, 'resources': {'autoScalingGroups': [{'name': 'asg'}]}}},
            'describe-auto-scaling-groups': {'AutoScalingGroups': [{'Instances': [{'InstanceId': 'i-test', 'LifecycleState': 'InService', 'HealthStatus': 'Healthy'}]}]},
            'get-metric-statistics': {'Datapoints': [{'Timestamp': '2026-09-16T12:00:00Z', 'Average': 20, 'Maximum': 0}, {'Timestamp': '2026-09-16T11:55:00Z', 'Average': 5, 'Maximum': 0}]},
        }[operation]

    def test_counts_health_and_latest_cpu(self):
        with patch.object(exporter, 'aws', side_effect=self.fake_aws):
            result = exporter.collect(['eu-west-3'])
        labels = 'region="eu-west-3",cluster="training",nodegroup="workers"'
        self.assertIn('aws_eks_nodegroup_nodes{' + labels + '} 1', result)
        self.assertIn('aws_eks_nodegroup_desired_nodes{' + labels + '} 2', result)
        self.assertIn('aws_eks_nodegroup_health_issues{' + labels + '} 1', result)
        self.assertIn('aws_eks_node_cpu_percent{' + labels + ',instance_id="i-test"} 20', result)

    def test_cloudwatch_failure_keeps_inventory(self):
        def call(region, service, operation, **kwargs):
            if service == 'cloudwatch':
                raise subprocess.TimeoutExpired('aws', 90)
            return self.fake_aws(region, service, operation, **kwargs)
        with patch.object(exporter, 'aws', side_effect=call):
            result = exporter.collect(['eu-west-3'])
        self.assertIn('aws_eks_clusters{region="eu-west-3"} 1', result)
        self.assertIn('stage="cloudwatch"} 0', result)
        self.assertNotIn('aws_eks_node_cpu_percent{', result)

    def test_missing_cloudwatch_point_is_not_zero(self):
        def call(region, service, operation, **kwargs):
            return {'Datapoints': []} if service == 'cloudwatch' else self.fake_aws(region, service, operation, **kwargs)
        with patch.object(exporter, 'aws', side_effect=call):
            result = exporter.collect(['eu-west-3'])
        self.assertNotIn('aws_eks_node_cpu_percent{', result)
        self.assertIn('stage="cloudwatch"} 1', result)

    def test_atomic_output_replaces_old_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'metrics.prom'
            output.write_text('old inventory')
            with patch.dict(exporter.os.environ, {'OUTPUT_FILE': str(output), 'EKS_REGIONS': 'eu-west-3'}), patch.object(exporter, 'aws', return_value={'clusters': []}):
                exporter.main()
            self.assertNotIn('old inventory', output.read_text())
            self.assertEqual(output.stat().st_mode & 0o777, 0o644)

    def test_dashboard_has_unique_panels(self):
        board = json.loads((ROOT / 'roles/access_docs/files/monitoring_grafana_eks.json').read_text())
        self.assertEqual(len(board['panels']), len({p['id'] for p in board['panels']}))
        self.assertEqual(board['uid'], 'tpcs-eks-overview')


if __name__ == '__main__':
    unittest.main()
