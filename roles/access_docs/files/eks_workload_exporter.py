#!/usr/bin/env python3
"""Read-only Kubernetes and tagged AWS resource inventory for the global dashboard."""
import base64
from collections import Counter
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

from eks_prom_exporter import aws, emit

ERRORS = (subprocess.SubprocessError, OSError, ValueError, KeyError)
HELP = {
    'pods_running': 'Pods in Running phase across all namespaces.',
    'pods': 'Pods by phase across all namespaces.',
    'csi_volumes': 'Persistent volumes using a CSI driver.',
    'csi_volumes_bound': 'CSI persistent volumes in Bound phase.',
    'csi_volume_info': 'CSI persistent volume identity and reclaim policy.',
    'csi_volume_attachments': 'VolumeAttachments with attached status true.',
    'loadbalancer_services': 'Kubernetes services of type LoadBalancer.',
    'loadbalancer_service_info': 'LoadBalancer service identity and provisioning status.',
    'node_memory_working_set_bytes': 'Node memory working set from kubelet summary in bytes.',
    'node_memory_percent': 'Node working set as percent of physical memory capacity.',
    'node_memory_timestamp_seconds': 'Unix timestamp of the kubelet memory observation.',
    'resource_info': 'AWS resource with Kubernetes tags, including resources of deleted clusters.',
    'regional_resources': 'Number of tagged AWS resources in a region by kind.',
    'regional_resource_review_candidates': 'Tagged AWS resources to review in a region, not proven orphans.',
    'resources': 'Tagged AWS resources per cluster and kind.',
    'resource_review_candidates': 'Tagged AWS resources to review per cluster and kind.',
    'detail_collection_success': 'Whether the latest collection stage succeeded.',
    'detail_collection_timestamp_seconds': 'Unix timestamp of the latest collection stage attempt.',
}
RESOURCE_KINDS = ('volume', 'snapshot', 'load_balancer', 'classic_load_balancer',
                  'target_group', 'network_interface', 'elastic_ip', 'security_group')


def attempt(lines, stage, labels, operation):
    part = []
    try:
        operation(part)
    except ERRORS as exc:
        # Do not print subprocess arguments or Kubernetes authorization tokens.
        print(f'EKS {labels} {stage}: {type(exc).__name__}', file=sys.stderr)
        emit(lines, 'detail_collection_success', 0, **labels, stage=stage)
        success = False
    else:
        lines.extend(part)
        emit(lines, 'detail_collection_success', 1, **labels, stage=stage)
        success = True
    emit(lines, 'detail_collection_timestamp_seconds', time.time(), **labels, stage=stage)
    return success


class Kubernetes:
    def __init__(self, region, cluster):
        info = aws(region, 'eks', 'describe-cluster', name=cluster)['cluster']
        self.endpoint = info['endpoint']
        self.tls = ssl.create_default_context(cadata=base64.b64decode(info['certificateAuthority']['data']).decode())
        self.token = aws(region, 'eks', 'get-token', cluster_name=cluster)['status']['token']

    def get(self, path):
        request = urllib.request.Request(self.endpoint + path, headers={'Authorization': 'Bearer ' + self.token})
        with urllib.request.urlopen(request, context=self.tls, timeout=15) as response:
            return json.load(response)

    def items(self, path):
        result = []
        continuation = ''
        while True:
            data = self.get(path + '?' + urllib.parse.urlencode({'limit': 500, 'continue': continuation}))
            result.extend(data['items'])
            continuation = data.get('metadata', {}).get('continue')
            if not continuation:
                return result


def workloads(api, labels, lines):
    pods = api.items('/api/v1/pods')
    emit(lines, 'pods_running', sum(p.get('status', {}).get('phase') == 'Running' for p in pods), **labels)
    for phase in ('Pending', 'Running', 'Succeeded', 'Failed', 'Unknown'):
        emit(lines, 'pods', sum(p.get('status', {}).get('phase', 'Unknown') == phase for p in pods), **labels, phase=phase)
    volumes = [p for p in api.items('/api/v1/persistentvolumes') if 'csi' in p.get('spec', {})]
    emit(lines, 'csi_volumes', len(volumes), **labels)
    emit(lines, 'csi_volumes_bound', sum(p.get('status', {}).get('phase') == 'Bound' for p in volumes), **labels)
    for pv in volumes:
        spec = pv['spec']
        emit(lines, 'csi_volume_info', 1, **labels, pv=pv['metadata']['name'],
             driver=spec['csi']['driver'], volume_id=spec['csi']['volumeHandle'],
             phase=pv.get('status', {}).get('phase', 'Unknown'),
             reclaim_policy=spec.get('persistentVolumeReclaimPolicy', 'Unknown'))
    attachments = api.items('/apis/storage.k8s.io/v1/volumeattachments')
    emit(lines, 'csi_volume_attachments', sum(a.get('status', {}).get('attached', False) for a in attachments), **labels)
    services = [s for s in api.items('/api/v1/services') if s.get('spec', {}).get('type') == 'LoadBalancer']
    emit(lines, 'loadbalancer_services', len(services), **labels)
    for service in services:
        emit(lines, 'loadbalancer_service_info', 1, **labels,
             namespace=service['metadata']['namespace'], service=service['metadata']['name'],
             provisioned=str(bool(service.get('status', {}).get('loadBalancer', {}).get('ingress'))).lower())


def memory(api, labels, lines):
    nodes = api.items('/api/v1/nodes')
    for node in nodes:
        name = node['metadata']['name']
        nl = dict(**labels, node=name, instance_id=node['spec'].get('providerID', '').rsplit('/', 1)[-1],
                  nodegroup=node['metadata'].get('labels', {}).get('eks.amazonaws.com/nodegroup', 'unmanaged'))
        def collect_node(part):
            data = api.get('/api/v1/nodes/' + urllib.parse.quote(name, safe='') + '/proxy/stats/summary')['node']['memory']
            stamp = dt.datetime.fromisoformat(data['time'].replace('Z', '+00:00')).timestamp()
            # availableBytes = capacity - workingSetBytes in kubelet summary API.
            working = data['workingSetBytes']
            capacity = working + data['availableBytes']
            if capacity <= 0:
                raise ValueError('Invalid node memory capacity')
            emit(part, 'node_memory_working_set_bytes', working, **nl)
            emit(part, 'node_memory_percent', 100 * working / capacity, **nl)
            emit(part, 'node_memory_timestamp_seconds', stamp, **nl)
        attempt(lines, 'memory_node', nl, collect_node)


def tagged_cluster(tags):
    """Return cluster attribution, unknown for Kubernetes tags without a cluster name."""
    tags = {t['Key']: t['Value'] for t in (tags or [])}
    for key in ('ebs.csi.aws.com/cluster-name', 'elbv2.k8s.aws/cluster', 'eks:cluster-name', 'KubernetesCluster'):
        if tags.get(key):
            return tags[key]
    for key in tags:
        if key.startswith('kubernetes.io/cluster/'):
            return key[len('kubernetes.io/cluster/'):]
    if any(k.startswith(('kubernetes.io/', 'ebs.csi.aws.com/', 'efs.csi.aws.com/', 'service.k8s.aws/', 'ingress.k8s.aws/'))
           or k in ('CSIVolumeName', 'CSIVolumeSnapshotName') for k in tags):
        return 'unknown'
    return None


def resource_rows(region, kind):
    """Yield (id, tags, state, review_reason). No dependency on live Kubernetes clusters."""
    configs = {
        'volume': ('describe-volumes', 'Volumes', 'VolumeId', 'State'),
        'snapshot': ('describe-snapshots', 'Snapshots', 'SnapshotId', 'State'),
        'network_interface': ('describe-network-interfaces', 'NetworkInterfaces', 'NetworkInterfaceId', 'Status'),
        'elastic_ip': ('describe-addresses', 'Addresses', 'AllocationId', None),
        'security_group': ('describe-security-groups', 'SecurityGroups', 'GroupId', None),
    }
    if kind in configs:
        operation, field, id_key, state_key = configs[kind]
        params = {'owner_ids': 'self'} if kind == 'snapshot' else {}
        for item in aws(region, 'ec2', operation, **params)[field]:
            state = item.get(state_key, 'present') if state_key else 'present'
            reason = ''
            if kind in ('volume', 'network_interface') and state == 'available':
                reason = 'detached'
            if kind == 'elastic_ip' and not item.get('AssociationId'):
                reason = 'unassociated'
            yield item[id_key], item.get('Tags', item.get('TagSet', [])), state, reason
    else:
        classic = kind == 'classic_load_balancer'
        service = 'elb' if classic else 'elbv2'
        target = kind == 'target_group'
        operation = 'describe-target-groups' if target else 'describe-load-balancers'
        field = 'TargetGroups' if target else ('LoadBalancerDescriptions' if classic else 'LoadBalancers')
        id_key = 'TargetGroupArn' if target else ('LoadBalancerName' if classic else 'LoadBalancerArn')
        for item in aws(region, service, operation)[field]:
            resource_id = item[id_key]
            param = {'load_balancer_names': resource_id} if classic else {'resource_arns': resource_id}
            tags = aws(region, service, 'describe-tags', **param)['TagDescriptions'][0]['Tags']
            reason = 'no_load_balancer' if target and not item.get('LoadBalancerArns') else ''
            yield resource_id, tags, item.get('State', {}).get('Code', 'present'), reason


def resources(region, clusters, lines):
    for kind in RESOURCE_KINDS:
        def collect_kind(part):
            counts = Counter({cluster: 0 for cluster in clusters})
            counts['unknown'] = 0
            candidates = Counter(counts)
            for resource_id, tags, state, reason in resource_rows(region, kind):
                cluster = tagged_cluster(tags)
                if cluster is None:
                    continue
                counts[cluster] += 1
                exists = 'unknown' if cluster == 'unknown' else str(cluster in clusters).lower()
                if exists == 'false':
                    reason = 'cluster_missing'
                elif cluster == 'unknown':
                    reason = reason or 'cluster_unknown'
                candidates[cluster] += bool(reason)
                emit(part, 'resource_info', 1, region=region, cluster=cluster, kind=kind,
                     resource_id=resource_id, state=state, cluster_exists=exists, review_reason=reason or 'none')
            emit(part, 'regional_resources', sum(counts.values()), region=region, kind=kind)
            emit(part, 'regional_resource_review_candidates', sum(candidates.values()), region=region, kind=kind)
            for cluster, count in counts.items():
                emit(part, 'resources', count, region=region, cluster=cluster, kind=kind)
                emit(part, 'resource_review_candidates', candidates[cluster], region=region, cluster=cluster, kind=kind)
        attempt(lines, kind, {'region': region}, collect_kind)


def collect(regions, mode):
    lines = []
    for region in regions:
        clusters = []
        def discover(part):
            clusters.extend(aws(region, 'eks', 'list-clusters')['clusters'])
        # Do not label resources orphaned when cluster discovery failed.
        if not attempt(lines, 'discovery', {'region': region}, discover):
            continue
        if mode == 'resources':
            resources(region, clusters, lines)
            continue
        for cluster in clusters:
            labels = {'region': region, 'cluster': cluster}
            def collect_cluster(part):
                api = Kubernetes(region, cluster)
                attempt(part, 'workloads', labels, lambda p: workloads(api, labels, p))
                attempt(part, 'memory', labels, lambda p: memory(api, labels, p))
            attempt(lines, 'kubernetes', labels, collect_cluster)
    names = sorted({line.split('{', 1)[0] for line in lines})
    metadata = [line for name in names for line in
                (f'# HELP {name} {HELP[name.removeprefix("aws_eks_")]}', f'# TYPE {name} gauge')]
    return '\n'.join(metadata + lines) + '\n'


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else 'workloads'
    if mode not in ('workloads', 'resources'):
        raise SystemExit('Expected workloads or resources')
    output = Path(os.environ.get('OUTPUT_FILE', f'/var/www/html/json/aws_eks_{mode}_metrics.prom'))
    with open(str(output) + '.lock', 'w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        content = collect(os.environ.get('EKS_REGIONS', 'eu-west-3').split(), mode)
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
