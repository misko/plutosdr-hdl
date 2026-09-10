"""One unchanged P1 diagnostic route of the audited checked-product DCP."""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

root=Path(__file__).resolve().parent
synthesis=root.parent/'checked-synthesis-parent.q1cr3TZZ'
source=synthesis/'run/synthesis/fft_bank_owned_synth.dcp'
runner=root.parent/'checked-product-physical-prepared-v2/route_completed_input_fence.tcl'
expected='62ea84c5d09ac3e41b00157d8761a1834d11540c28566196148b8e74bb70ba52'
runner_sha='0873675fcec384f676a80b75b746460fbff2ecc3ee162f6111705ead2fad6d4a'
output=root/'route'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
for path in (source,runner,output):
    assert path.is_absolute() and '..' not in path.parts and not any(p.is_symlink() for p in (path,*path.parents))
assert sha(source)==expected and sha(runner)==runner_sha and not output.exists()
audit=json.loads((synthesis/'audit.json').read_text())
assert audit['dcp_sha256']==expected and audit['source_hierarchy_resources_verified'] and audit['fixed_clock_source_verified']
execution=json.loads((synthesis/'execution.json').read_text())
assert execution['owner_exit']==0 and not execution['timed_out'] and not execution['prepared_changed'] and not execution['live_changed']
text=runner.read_text()
assert 'opt_design\nplace_design\nphys_opt_design\nroute_design\n' in text
assert not any(x in text for x in ('set_false_path','set_multicycle_path','set_clock_groups','create_clock','read_xdc'))
env={k:v for k,v in os.environ.items() if k not in ('PYTHONHOME','PYTHONPATH','PYTHONOPTIMIZE','LD_LIBRARY_PATH')}
env['LD_LIBRARY_PATH']='/opt/Xilinx/Vivado/2022.2/lib/lnx64.o/SuSE'
(root/'tmp').mkdir();env['TMPDIR']=str(root/'tmp')
cmd=['/opt/Xilinx/Vivado/2022.2/bin/vivado','-mode','batch','-notrace','-source',str(runner),
'-log',str(root/'vivado.log'),'-journal',str(root/'vivado.jou'),'-tclargs',str(source),expected,str(output)]
(root/'command.json').write_text(json.dumps({'command':cmd,'source_sha256':expected,'runner_sha256':runner_sha,'timeout_seconds':900,'scope':'isolated diagnostic route, not release'},indent=2))
start=time.monotonic();timeout=False;interruption=None
with (root/'stdout.log').open('x') as log:
    p=subprocess.Popen(cmd,cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
    (root/'process.json').write_text(json.dumps({'pid':p.pid,'process_group':p.pid}))
    print('Root checked-product diagnostic route started pid='+str(p.pid),flush=True)
    try:code=p.wait(timeout=900)
    except (subprocess.TimeoutExpired,KeyboardInterrupt) as error:
        timeout=isinstance(error,subprocess.TimeoutExpired);interruption=type(error).__name__
        try:os.killpg(p.pid,signal.SIGTERM)
        except ProcessLookupError:pass
        try:code=p.wait(timeout=10)
        except subprocess.TimeoutExpired:
            try:os.killpg(p.pid,signal.SIGKILL)
            except ProcessLookupError:pass
            code=p.wait(timeout=10)
routed=output/'completed_input_diagnostic_routed.dcp'
result={'vendor_exit':code,'timed_out':timeout,'interruption':interruption,'wall_seconds':time.monotonic()-start,
        'source_dcp_unchanged':sha(source)==expected,'original_runner_unchanged':sha(runner)==runner_sha,
        'copied_runner_unchanged':(output/'probe.tcl').is_file() and sha(output/'probe.tcl')==runner_sha,
        'routed_dcp_sha256':sha(routed) if routed.is_file() else None,'deployment_eligible':False}
(root/'execution.json').write_text(json.dumps(result,indent=2))
print('\n'.join((root/'stdout.log').read_text().splitlines()[-20:]),flush=True)
print(json.dumps(result),flush=True)
assert code==0 and not timeout and interruption is None and all(result[k] for k in ('source_dcp_unchanged','original_runner_unchanged','copied_runner_unchanged','routed_dcp_sha256'))
