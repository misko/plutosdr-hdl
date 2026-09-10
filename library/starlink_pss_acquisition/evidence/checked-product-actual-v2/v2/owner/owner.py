"""Root-owned one-shot actual FFT run; process success is not result acceptance."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time

out=Path(__file__).resolve().parent
prepared=out.parent/'checked-product-actual-prepared-v2'
gate=out.parent/'checked-drain-prep-parent.TQPsrJdl'
tree=Path('/tmp/starlink-rom-prefetch.j829ht/fw')
python=Path('/home/mouse9911/.local/share/uv/python/cpython-3.11.16-linux-x86_64-gnu/bin/python3.11')
cli=prepared/'prepare_checked_product_drain_actual.py'
project=prepared/'project'
expected='55288860074df8107d142c97bd69cb67bc71815f13bbb8bacc3b664b9547f5ea'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(name,value):
    with (out/name).open('x') as f:json.dump(value,f,indent=2)
assert sha(python)=='2874a0b9344d06b7767aebb1e6e25a759ffcbdb544e99400ecc74dc6092d1174'
assert sha(Path('/home/mouse9911/gits/pluto-plus-utils/.venv/bin/python'))==sha(python)
assert not any(p.exists() for p in (project,out/'stdout.log',out/'vivado.log',out/'vivado.jou',out/'process.json',out/'execution.json'))
assert shutil.disk_usage(out).free>2*1024**3
review=json.loads((gate/'audit.json').read_text())
assert review['exit']==0 and review['sources_unchanged'] and review['prepared_unchanged'] and not review['vendor_run']
assert review['tests']==76 and review['source_count']==34 and review['prepared_count']==89
live=json.loads((gate/'source-pins.json').read_text())
assert all(sha(tree/n)==v for n,v in live.items())
assert sha(prepared/'SHA256SUMS')==expected
pins=json.loads((gate/'prepared-pins.json').read_text())
assert len(pins)==89 and all(sha(prepared/n)==v for n,v in pins.items())
write('input-pins.json',{'manifest':expected,'files':pins,'live':live,'python_sha256':sha(python)})
env={k:v for k,v in os.environ.items() if k not in ('PYTHONHOME','PYTHONPATH','PYTHONOPTIMIZE','LD_LIBRARY_PATH')}
temporary=out/'tmp';temporary.mkdir()
env['TMPDIR']=str(temporary)
pre=subprocess.run([str(python),'-B',str(cli),'--verify-prepared',str(prepared)],cwd='/',env=env,
 capture_output=True,text=True,timeout=30)
write('preparation-check.json',{'exit':pre.returncode,'stdout':pre.stdout,'stderr':pre.stderr})
assert pre.returncode==0 and json.loads(pre.stdout)['CHECKED_PRODUCT_BANK']==1,pre.stderr
cmd=['/opt/Xilinx/Vivado/2022.2/bin/vivado','-mode','batch','-notrace','-source',
 str(prepared/'frozen_sources/simulate_exact_control_prepared.tcl'),'-log',str(out/'vivado.log'),
 '-journal',str(out/'vivado.jou'),'-tclargs',str(prepared)]
write('command.json',cmd)
vendor_env=dict(env,LD_LIBRARY_PATH='/opt/Xilinx/Vivado/2022.2/lib/lnx64.o/SuSE')
start=time.monotonic();timed_out=False;interruption=None
with (out/'stdout.log').open('x') as log:
    p=subprocess.Popen(cmd,cwd=out,env=vendor_env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
    write('process.json',{'pid':p.pid,'started_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'timeout_seconds':600})
    try:p.wait(timeout=600)
    except subprocess.TimeoutExpired:
        timed_out=True;os.killpg(p.pid,signal.SIGTERM)
        try:p.wait(timeout=10)
        except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
    except BaseException as error:
        interruption=type(error).__name__+': '+str(error)
        os.killpg(p.pid,signal.SIGTERM)
        try:p.wait(timeout=10)
        except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
execution={'vendor_exit':p.returncode,'timed_out':timed_out,'interruption':interruption,'elapsed_seconds':time.monotonic()-start}
write('execution.json',execution)
# These audits are unconditional on normal process failure or timeout.
source_errors=[]
for n,digest in pins.items():
    try:
        if sha(prepared/n)!=digest:source_errors.append(n)
    except Exception as error:source_errors.append(n+': '+str(error))
live_errors=[]
for n,digest in live.items():
    try:
        if sha(tree/n)!=digest:live_errors.append(n)
    except Exception as error:live_errors.append(n+': '+str(error))
manifest_ok=sha(prepared/'SHA256SUMS')==expected
write('after-sources.json',{'manifest_unchanged':manifest_ok,'source_errors':source_errors,'live_errors':live_errors})
ip={str(p.relative_to(project)):{'bytes':p.stat().st_size,'sha256':sha(p)}
    for p in sorted(project.rglob('*')) if p.is_file() and not p.is_symlink() and p.suffix in ('.xci','.vhd')}
write('generated-ip-after.json',{'scope':'generated-after-run plus independently known wrapper identity; no pre-generation equality claim','files':ip})
wrapper=project/'exact_control_actual.gen/sources_1/ip/starlink_pss_fft512_bfp18_rt_candidate/synth/starlink_pss_fft512_bfp18_rt_candidate.vhd'
wrapper_ok=wrapper.is_file() and sha(wrapper)=='a3a650654118016012bdfb8553114ee4a89866466d8ca774fa0f281640168a68'
post=subprocess.run([str(python),'-B',str(cli),'--verify-result',str(prepared)],cwd='/',env=env,
 capture_output=True,text=True,timeout=90)
write('result-check.json',{'exit':post.returncode,'stdout':post.stdout,'stderr':post.stderr})
accepted=p.returncode==0 and not timed_out and interruption is None and manifest_ok and not source_errors and not live_errors and wrapper_ok and post.returncode==0
result=dict(execution,source_pins_unchanged=manifest_ok and not source_errors,live_sources_unchanged=not live_errors,
 generated_wrapper_matches_known=wrapper_ok,result_exit=post.returncode,functional_accepted=accepted,
 physical_qualified=False,deployment_eligible=False)
write('outcome.json',result)
print(json.dumps(result))
if post.returncode==0:print(post.stdout)
else:print(post.stderr[-5000:])
raise SystemExit(0 if accepted else 1)
