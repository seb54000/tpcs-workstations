#!/usr/bin/env python3
"""Collect software versions only; no credentials, environment or Terraform state."""
import json, pathlib, subprocess, shlex, tempfile, sys
root=pathlib.Path(__file__).resolve().parent
code=r'''
import json,subprocess,pathlib

def output(args):
 p=subprocess.run(args,capture_output=True,text=True)
 return {'rc':p.returncode,'stdout':p.stdout.strip(),'stderr':p.stderr.strip()}
p=output(['dpkg-query','-W','-f=${binary:Package}\t${Version}\t${db:Status-Status}\n'])
packages={}
for line in p['stdout'].splitlines():
 name,version,status=line.split('\t')
 if status=='installed':packages[name]=version
r={'packages':packages,'os_release':pathlib.Path('/etc/os-release').read_text(),'python':output(['python3','--version'])}
for name,path in [('node','/usr/bin/node'),('npm','/usr/bin/npm'),('nginx','/usr/sbin/nginx'),('postgres','/usr/bin/psql'),('redis','/usr/bin/redis-server'),('aws','/usr/local/bin/aws')]:
 if pathlib.Path(path).exists():r[name]=output([path,'-v' if name=='nginx' else '--version'])
for role in ['api','worker']:
 p=pathlib.Path('/opt/demoboard')/(role+'-service/.venv/bin/pip')
 if p.exists():
  r[role+'_pip']=output([str(p),'freeze','--all'])
  r[role+'_pip_check']=output([str(p),'check'])
p=pathlib.Path('/opt/demoboard/frontend-service/package-lock.json')
if p.exists():
 data=json.loads(p.read_text());r['frontend_dependencies']={k:data['packages']['node_modules/'+k]['version'] for k in ['vue','vite','@vitejs/plugin-vue']}
print(json.dumps(r))
'''
with tempfile.TemporaryDirectory(prefix='tpcs-software-') as tmp:
 p=subprocess.run([str(pathlib.Path(sys.executable).with_name('ansible')),'-i','aws_ec2.yml','_Role_front:_Role_api:_Role_worker:_Role_db:_Role_redis','-m','ansible.builtin.shell','-a','python3 -c '+shlex.quote(code),'--tree',tmp],cwd=root,capture_output=True,text=True)
 if p.returncode:raise RuntimeError(p.stdout+p.stderr)
 data={f.name:json.loads(json.loads(f.read_text())['stdout']) for f in pathlib.Path(tmp).iterdir()}
 print(json.dumps(data,indent=2))
