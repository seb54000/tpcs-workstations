"""Offline checks; requires sibling monitoring and demoboard checkouts, PyYAML and Jinja2."""
from pathlib import Path
import json,re,subprocess,tempfile,shlex,yaml
from jinja2 import Environment,StrictUndefined
W=Path(__file__).resolve().parents[2];M=W.parent/'tp-cs-monitoring-student';D=W.parent/'tpcs-demoboard'
lock=json.loads((W/'versions/baselines/tpmon-2026-10-01/images.lock.json').read_text())
p=W/'roles/student/templates/tpmon/eks_demoboard_monitoring_lgtm.sh.j2';s=p.read_text()
for filename in ['eks_demoboard_monitoring_lgtm.sh.j2','refresh_grafana_lgtm.sh.j2']:
 rendered=Environment(undefined=StrictUndefined).from_string((p.parent/filename).read_text()).render(ansible_hostname='vm00',dns_subdomain='example.test',tf_vars={})
 subprocess.run(['bash','-n'],input=rendered,text=True,check=True)
for rel in ['03-demoboard/kubernetes/monitoring-lgtm.eks.yaml','03-demoboard/docker-compose.lgtm.yaml']:
 text=(M/rel).read_text();list(yaml.safe_load_all(text))
 refs=re.findall(r'^\s*image:\s*(\S+)',text,re.M);assert refs and all('@sha256:' in r for r in refs)
start=s.index('cp "$MONITORING_SRC"');end=s.index('echo "== Deploy LGTM monitoring stack on EKS =="')
segment=s[start:end]
with tempfile.TemporaryDirectory() as tmp:
 root=Path(tmp); mon=root/'source.yaml';mon.write_text((M/'03-demoboard/kubernetes/monitoring-lgtm.eks.yaml').read_text())
 v={'MONITORING_SRC':str(mon),'DEMO_V1_SRC':str(D/'demoboard-kubernetes-observability.yml'),'DEMO_V2_SRC':str(D/'demoboard-kubernetes-observability-scaled.yml'),'MONITORING_OUT':str(root/'mon.yaml'),'DEMO_V1_OUT':str(root/'v1.yaml'),'DEMO_V2_OUT':str(root/'v2.yaml'),'NS':'vm07','CLUSTER_SUFFIX':'eks02','DNS_SUBDOMAIN':'test.invalid','IMAGE_REPO_URL':'example.ecr/repo','API_DIGEST':lock['demoboard']['api-v1'],'WORKER_DIGEST':lock['demoboard']['worker-v1'],'FRONT_DIGEST':lock['demoboard']['front-v2']}
 script='\n'.join(k+'='+shlex.quote(x) for k,x in v.items())+'\n'+segment
 subprocess.run(['bash','-eu'],input=script,text=True,check=True,capture_output=True)
 for out in ['MONITORING_OUT','DEMO_V1_OUT','DEMO_V2_OUT']:
  text=Path(v[out]).read_text();list(yaml.safe_load_all(text));refs=re.findall(r'^\s*image:\s*(\S+)',text,re.M)
  assert refs and all(re.fullmatch(r'.+@sha256:[a-f0-9]{64}',x) for x in refs)
  assert 'vm00' not in text and 'tpcsonline.org' not in text
 mon.write_text(mon.read_text()+'\nimage: unreviewed:latest\n')
 result=subprocess.run(['bash','-eu'],input=script,text=True,capture_output=True);assert result.returncode!=0 and 'floating image' in result.stderr
print('OK: shell syntax, YAML, v1/scaled generation, namespace substitution, digest-only images, rejection of unknown floating image.')
