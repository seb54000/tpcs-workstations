#!/usr/bin/env python3
"""Export regional AWS quota limits, usage and inventory as Prometheus metrics."""
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
DEFAULT_REGIONS = (
    'eu-central-1 eu-west-1 eu-west-2 eu-west-3 eu-south-1 eu-south-2 '
    'eu-north-1 eu-central-2'
)
SERVICES = ('ec2', 'vpc', 'elasticloadbalancing')

# For quotas without a CloudWatch UsageMetric, use the matching live inventory.
# Keep these names aligned with the names returned by Service Quotas.
INVENTORY_QUOTAS = {
    'VPCs per Region': ('vpcs', None),
    'VPC security groups per Region': ('security_groups', None),
    'Subnets per VPC': ('subnets', 'vpc_id'),
    'Route tables per VPC': ('route_tables', 'vpc_id'),
    'Network ACLs per VPC': ('network_acls', 'vpc_id'),
    'Network interfaces per Region': ('network_interfaces', None),
    'Elastic IP addresses per Region': ('elastic_ips', None),
    'Internet gateways per Region': ('internet_gateways', None),
    'NAT gateways per Availability Zone': ('nat_gateways', 'availability_zone'),
    'Target groups per Region': ('target_groups', None),
    'Application Load Balancers per Region': ('load_balancers', 'type:application'),
    'Network Load Balancers per Region': ('load_balancers', 'type:network'),
    'Gateway Load Balancers per Region': ('load_balancers', 'type:gateway'),
    'Classic Load Balancers per Region': ('load_balancers', 'type:classic'),
}


def aws(region, service, operation, **kwargs):
    command = [AWS, service, operation, '--region', region, '--output', 'json',
               '--cli-connect-timeout', '10', '--cli-read-timeout', '30']
    for key, value in kwargs.items():
        command.extend(['--' + key.replace('_', '-'), str(value)])
    result = subprocess.run(command, check=True, capture_output=True, text=True,
                            timeout=90,
                            env={**os.environ, 'AWS_PAGER': '', 'AWS_MAX_ATTEMPTS': '2'})
    return json.loads(result.stdout)


def emit(lines, metric, value, **labels):
    encoded = ','.join(
        f'{key}={json.dumps(str(val), ensure_ascii=False)}'
        for key, val in labels.items() if val is not None
    )
    lines.append(f'aws_{metric}{{{encoded}}} {value}')


def inventory(region, lines):
    counts = {}

    vpcs = aws(region, 'ec2', 'describe-vpcs')['Vpcs']
    counts['vpcs'] = len(vpcs)
    emit(lines, 'quota_inventory_count', len(vpcs), region=region,
         resource='vpcs', scope='region')

    subnet_counts = {}
    for vpc in vpcs:
        subnet_counts[vpc['VpcId']] = 0
    for subnet in aws(region, 'ec2', 'describe-subnets')['Subnets']:
        vpc_id = subnet['VpcId']
        subnet_counts[vpc_id] = subnet_counts.get(vpc_id, 0) + 1
        emit(lines, 'subnet_available_ipv4_addresses', subnet.get('AvailableIpAddressCount', 0),
             region=region, vpc_id=vpc_id, subnet_id=subnet['SubnetId'],
             availability_zone=subnet['AvailabilityZone'])
    for vpc_id, count in subnet_counts.items():
        emit(lines, 'quota_inventory_count', count, region=region,
             resource='subnets', scope='vpc', vpc_id=vpc_id)
    counts['subnets_by_vpc'] = subnet_counts

    for resource, operation, response_key in (
        ('route_tables', 'describe-route-tables', 'RouteTables'),
        ('network_acls', 'describe-network-acls', 'NetworkAcls'),
    ):
        by_vpc = {}
        for item in aws(region, 'ec2', operation)[response_key]:
            vpc_id = item['VpcId']
            by_vpc[vpc_id] = by_vpc.get(vpc_id, 0) + 1
        counts[resource + '_by_vpc'] = by_vpc
        for vpc_id, count in by_vpc.items():
            emit(lines, 'quota_inventory_count', count, region=region,
                 resource=resource, scope='vpc', vpc_id=vpc_id)

    security_groups = aws(region, 'ec2', 'describe-security-groups')['SecurityGroups']
    counts['security_groups'] = len(security_groups)
    emit(lines, 'quota_inventory_count', len(security_groups), region=region,
         resource='security_groups', scope='region')

    instances_by_state = {}
    instances = [instance for reservation in aws(region, 'ec2', 'describe-instances')['Reservations']
                 for instance in reservation['Instances']]
    for instance in instances:
        state = instance['State']['Name']
        instances_by_state[state] = instances_by_state.get(state, 0) + 1
    counts['instances'] = sum(n for state, n in instances_by_state.items()
                              if state not in ('terminated', 'shutting-down'))
    for state, count in instances_by_state.items():
        emit(lines, 'quota_inventory_count', count, region=region,
             resource='instances', scope='region', state=state)

    network_interfaces = aws(region, 'ec2', 'describe-network-interfaces')['NetworkInterfaces']
    counts['network_interfaces'] = len(network_interfaces)
    emit(lines, 'quota_inventory_count', len(network_interfaces), region=region,
         resource='network_interfaces', scope='region')

    elastic_ips = aws(region, 'ec2', 'describe-addresses')['Addresses']
    counts['elastic_ips'] = len(elastic_ips)
    emit(lines, 'quota_inventory_count', len(elastic_ips), region=region,
         resource='elastic_ips', scope='region')

    internet_gateways = aws(region, 'ec2', 'describe-internet-gateways')['InternetGateways']
    counts['internet_gateways'] = len(internet_gateways)
    emit(lines, 'quota_inventory_count', len(internet_gateways), region=region,
         resource='internet_gateways', scope='region')

    nat_gateways = [gateway for gateway in aws(region, 'ec2', 'describe-nat-gateways')['NatGateways']
                    if gateway.get('State') not in ('deleted', 'failed')]
    counts['nat_gateways'] = len(nat_gateways)
    emit(lines, 'quota_inventory_count', len(nat_gateways), region=region,
         resource='nat_gateways', scope='region')
    nat_by_az = {}
    for gateway in nat_gateways:
        az = gateway.get('AvailabilityZone', 'unknown')
        nat_by_az[az] = nat_by_az.get(az, 0) + 1
    for az, count in nat_by_az.items():
        emit(lines, 'quota_inventory_count', count, region=region,
             resource='nat_gateways', scope='availability_zone', availability_zone=az)
    counts['nat_gateways_by_az'] = nat_by_az

    lbs = aws(region, 'elbv2', 'describe-load-balancers')['LoadBalancers']
    classic_lbs = aws(region, 'elb', 'describe-load-balancers')['LoadBalancerDescriptions']
    lb_counts = {}
    for lb in lbs:
        lb_type = lb.get('Type', 'unknown')
        lb_counts[lb_type] = lb_counts.get(lb_type, 0) + 1
    lb_counts['classic'] = len(classic_lbs)
    counts['load_balancers_by_type'] = lb_counts
    for lb_type, count in lb_counts.items():
        emit(lines, 'quota_inventory_count', count, region=region,
             resource='load_balancers', scope='region', type=lb_type)

    target_groups = aws(region, 'elbv2', 'describe-target-groups')['TargetGroups']
    counts['target_groups'] = len(target_groups)
    emit(lines, 'quota_inventory_count', len(target_groups), region=region,
         resource='target_groups', scope='region')

    return counts


def inventory_usage(name, labels, counts):
    mapping = INVENTORY_QUOTAS.get(name)
    if not mapping:
        return None
    resource, selector = mapping
    context = (labels.get('context_id') or '').rsplit('/', 1)[-1]
    if resource == 'subnets':
        return counts.get('subnets_by_vpc', {}).get(context) if context else None
    if resource in ('route_tables', 'network_acls'):
        return counts.get(resource + '_by_vpc', {}).get(context) if context else None
    if resource == 'nat_gateways':
        return counts.get('nat_gateways_by_az', {}).get(context) if context else None
    if resource == 'load_balancers':
        lb_type = selector.split(':', 1)[1]
        return counts.get('load_balancers_by_type', {}).get(lb_type)
    return counts.get(resource)


def collect_quotas(region, inventory_counts, lines):
    quotas = []
    for service in SERVICES:
        data = aws(region, 'service-quotas', 'list-service-quotas',
                   service_code=service, quota_applied_at_level='ALL')
        quotas.extend(data.get('Quotas', []))

    metric_queries = []
    query_quotas = {}
    for quota in quotas:
        service = quota['ServiceCode']
        code = quota['QuotaCode']
        name = quota['QuotaName']
        context = (quota.get('QuotaContext') or {}).get('ContextId')
        scope = (quota.get('QuotaAppliedAtLevel') or
                 ('RESOURCE' if context else 'ACCOUNT'))
        labels = dict(region=region, service=service, quota_code=code,
                      quota_name=name, scope=scope, context_id=context,
                      unit=quota.get('Unit'), adjustable=quota.get('Adjustable'),
                      global_quota=quota.get('GlobalQuota'))
        limit = quota.get('Value')
        if limit is not None:
            emit(lines, 'service_quota_limit', limit, **labels)

        metric = quota.get('UsageMetric') or {}
        dimensions = metric.get('MetricDimensions') or {}
        if limit is not None and metric.get('MetricName') and metric.get('MetricNamespace') and dimensions:
            query_id = f'q{len(metric_queries):04d}'
            statistic = quota.get('MetricStatisticRecommendation', 'Maximum')
            metric_queries.append({
                'Id': query_id,
                'MetricStat': {
                    'Metric': {
                        'Namespace': metric['MetricNamespace'],
                        'MetricName': metric['MetricName'],
                        'Dimensions': [{'Name': key, 'Value': value}
                                       for key, value in sorted(dimensions.items())],
                    },
                    'Period': 60,
                    'Stat': statistic if statistic in ('Sum', 'Maximum') else 'Maximum',
                },
                'ReturnData': True,
            })
            query_quotas[query_id] = (quota, labels)
            continue

        if limit is None:
            continue
        usage = inventory_usage(name, labels, inventory_counts)
        if usage is not None:
            emit(lines, 'service_quota_usage', usage, **labels, source='inventory')
            if limit > 0:
                emit(lines, 'service_quota_utilization_percent', usage * 100 / limit, **labels)
                emit(lines, 'service_quota_remaining', limit - usage, **labels)

    if not metric_queries:
        return True

    end = dt.datetime.now(dt.timezone.utc)
    start = end - dt.timedelta(minutes=15)
    # CloudWatch GetMetricData accepts at most 500 queries per request.
    cloudwatch_success = True
    populated_ids = set()
    for offset in range(0, len(metric_queries), 500):
        batch = metric_queries[offset:offset + 500]
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as source:
            json.dump(batch, source)
            query_file = source.name
        try:
            try:
                result = aws(region, 'cloudwatch', 'get-metric-data',
                             metric_data_queries='file://' + query_file,
                             start_time=start.isoformat(), end_time=end.isoformat(),
                             scan_by='TimestampDescending')
            except (subprocess.SubprocessError, OSError, ValueError) as exc:
                cloudwatch_success = False
                print(f'AWS quota exporter {region} cloudwatch: {type(exc).__name__}', file=sys.stderr)
                continue
        finally:
            os.unlink(query_file)
        for item in result.get('MetricDataResults', []):
            if item.get('StatusCode') not in (None, 'Complete'):
                cloudwatch_success = False
            if not item.get('Values'):
                continue
            populated_ids.add(item['Id'])
            quota, labels = query_quotas[item['Id']]
            usage = item['Values'][0]
            limit = quota.get('Value')
            emit(lines, 'service_quota_usage', usage, **labels, source='cloudwatch')
            if limit and limit > 0:
                emit(lines, 'service_quota_utilization_percent', usage * 100 / limit, **labels)
                emit(lines, 'service_quota_remaining', limit - usage, **labels)

    # AWS sometimes supplies usage metric metadata before a datapoint exists.
    # Use live inventory only when an exact quota-to-resource mapping is known.
    for query_id, (quota, labels) in query_quotas.items():
        if query_id in populated_ids:
            continue
        usage = inventory_usage(quota['QuotaName'], labels, inventory_counts)
        limit = quota.get('Value')
        if usage is not None and limit and limit > 0:
            emit(lines, 'service_quota_usage', usage, **labels, source='inventory')
            emit(lines, 'service_quota_utilization_percent', usage * 100 / limit, **labels)
            emit(lines, 'service_quota_remaining', limit - usage, **labels)
    return cloudwatch_success


def collect(regions):
    lines = []
    for region in regions:
        counts = None
        inventory_lines = []
        try:
            counts = inventory(region, inventory_lines)
        except (subprocess.SubprocessError, OSError, ValueError, KeyError) as exc:
            print(f'AWS quota exporter {region} inventory: {type(exc).__name__}', file=sys.stderr)
            emit(lines, 'quota_collection_success', 0, region=region, stage='inventory')
        else:
            lines.extend(inventory_lines)
            emit(lines, 'quota_collection_success', 1, region=region, stage='inventory')

        try:
            cloudwatch_success = collect_quotas(region, counts or {}, lines)
        except (subprocess.SubprocessError, OSError, ValueError, KeyError, TypeError) as exc:
            print(f'AWS quota exporter {region} quotas: {type(exc).__name__}', file=sys.stderr)
            emit(lines, 'quota_collection_success', 0, region=region, stage='quotas')
        else:
            emit(lines, 'quota_collection_success', 1, region=region, stage='quotas')
            emit(lines, 'quota_collection_success', int(cloudwatch_success),
                 region=region, stage='cloudwatch')
        emit(lines, 'quota_collection_timestamp_seconds', time.time(), region=region)

    names = sorted({line.split('{', 1)[0] for line in lines})
    return '\n'.join([f'# TYPE {name} gauge' for name in names] + lines) + '\n'


def main():
    output = Path(os.environ.get('OUTPUT_FILE', '/var/www/html/json/aws_quotas_metrics.prom'))
    regions = os.environ.get('AWS_QUOTA_REGIONS', DEFAULT_REGIONS).split()
    output.parent.mkdir(parents=True, exist_ok=True)
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
