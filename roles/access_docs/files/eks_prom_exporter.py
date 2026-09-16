#!/usr/bin/env python3
"""AWS CLI based EKS inventory; no Kubernetes access or Python dependencies required."""
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

AWS = os.environ.get('AWS_CLI') or shutil.which('aws') or '/usr/local/bin/aws'


def aws(region, service, operation, **kwargs):
    command = [AWS, service, operation, '--region', region, '--output', 'json',
               '--cli-connect-timeout', '10', '--cli-read-timeout', '30']
    for key, value in kwargs.items():
        command.extend(['--' + key.replace('_', '-'), str(value)])
    result = subprocess.run(command, check=True, capture_output=True, text=True,
                            timeout=90, env={**os.environ, 'AWS_PAGER': '', 'AWS_MAX_ATTEMPTS': '2'})
    return json.loads(result.stdout)


def emit(lines, name, value, **labels):
    # JSON string escaping matches Prometheus for AWS label values.
    label_text = ','.join(f'{key}={json.dumps(str(val), ensure_ascii=False)}' for key, val in labels.items())
    lines.append(f'aws_eks_{name}{{{label_text}}} {value}')


def inventory(region, lines):
    clusters = aws(region, 'eks', 'list-clusters')['clusters']
    emit(lines, 'clusters', len(clusters), region=region)
    nodes = []
    for cluster in clusters:
        labels = dict(region=region, cluster=cluster)
        info = aws(region, 'eks', 'describe-cluster', name=cluster)['cluster']
        emit(lines, 'cluster_info', 1, **labels, status=info['status'], version=info['version'])
        emit(lines, 'cluster_health_issues', len(info.get('health', {}).get('issues', [])), **labels)
        groups = aws(region, 'eks', 'list-nodegroups', cluster_name=cluster)['nodegroups']
        emit(lines, 'nodegroups', len(groups), **labels)
        for group in groups:
            gl = dict(**labels, nodegroup=group)
            ng = aws(region, 'eks', 'describe-nodegroup', cluster_name=cluster, nodegroup_name=group)['nodegroup']
            emit(lines, 'nodegroup_info', 1, **gl, status=ng['status'])
            emit(lines, 'nodegroup_health_issues', len(ng.get('health', {}).get('issues', [])), **gl)
            for key in ('minSize', 'maxSize', 'desiredSize'):
                if key in ng.get('scalingConfig', {}):
                    emit(lines, 'nodegroup_' + key.removesuffix('Size') + '_nodes', ng['scalingConfig'][key], **gl)
            members = {}
            for asg in ng.get('resources', {}).get('autoScalingGroups', []):
                data = aws(region, 'autoscaling', 'describe-auto-scaling-groups', auto_scaling_group_names=asg['name'])
                for item in data['AutoScalingGroups']:
                    for node in item['Instances']:
                        members[node['InstanceId']] = node
            emit(lines, 'nodegroup_nodes', len(members), **gl)
            for instance_id, node in members.items():
                nl = dict(**gl, instance_id=instance_id)
                emit(lines, 'node_info', 1, **nl, lifecycle=node['LifecycleState'], health=node['HealthStatus'])
                nodes.append(nl)
    return nodes


def cloudwatch(region, nodes, lines):
    now = dt.datetime.now(dt.timezone.utc)
    for labels in nodes:
        for metric, suffix, statistic in [('CPUUtilization', 'node_cpu_percent', 'Average'),
                                           ('StatusCheckFailed', 'node_status_check_failed', 'Maximum')]:
            result = aws(region, 'cloudwatch', 'get-metric-statistics', namespace='AWS/EC2',
                         metric_name=metric, dimensions='Name=InstanceId,Value=' + labels['instance_id'],
                         start_time=(now - dt.timedelta(minutes=15)).isoformat(), end_time=now.isoformat(),
                         period=300, statistics=statistic)
            points = result['Datapoints']
            if points:
                latest = max(points, key=lambda p: p['Timestamp'])
                stamp = dt.datetime.fromisoformat(latest['Timestamp'].replace('Z', '+00:00')).timestamp()
                emit(lines, suffix, latest[statistic], **labels)
                emit(lines, suffix + '_timestamp_seconds', stamp, **labels)


def collect(regions):
    lines = []
    for region in regions:
        for stage in ('inventory', 'cloudwatch'):
            part = []
            try:
                if stage == 'inventory':
                    nodes = inventory(region, part)
                else:
                    cloudwatch(region, nodes, part)
            except (subprocess.SubprocessError, OSError, ValueError, KeyError) as exc:
                print(f'EKS {region} {stage}: {type(exc).__name__}', file=sys.stderr)
                emit(lines, 'collection_success', 0, region=region, stage=stage)
                if stage == 'inventory':
                    break
            else:
                lines.extend(part)
                emit(lines, 'collection_success', 1, region=region, stage=stage)
        emit(lines, 'collection_timestamp_seconds', time.time(), region=region)
    names = sorted({line.split('{', 1)[0] for line in lines})
    return '\n'.join([f'# TYPE {name} gauge' for name in names] + lines) + '\n'


def main():
    output = Path(os.environ.get('OUTPUT_FILE', '/var/www/html/json/aws_eks_metrics.prom'))
    regions = os.environ.get('EKS_REGIONS', 'eu-west-3').split()
    with open(str(output) + '.lock', 'w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        content = collect(regions)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode='w', dir=output.parent, delete=False) as target:
                temporary = target.name
                target.write(content)
                os.fchmod(target.fileno(), 0o644)
            os.replace(temporary, output)
        finally:
            if temporary and os.path.exists(temporary):
                os.unlink(temporary)


if __name__ == '__main__':
    main()
