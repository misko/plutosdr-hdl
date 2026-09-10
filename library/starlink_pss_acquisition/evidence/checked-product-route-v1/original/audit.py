"""Audit the completed isolated route without mistaking execution for closure."""
import hashlib
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parent
route = root / 'route'
synth = root.parent / 'checked-synthesis-parent.q1cr3TZZ/run/synthesis'
execution = json.loads((root / 'execution.json').read_text())
assert execution['vendor_exit'] == 0 and execution['timed_out'] is False
assert execution['interruption'] is None
assert all(execution[k] is True for k in (
    'source_dcp_unchanged', 'original_runner_unchanged', 'copied_runner_unchanged'))
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
assert sha(synth / 'fft_bank_owned_synth.dcp') == '62ea84c5d09ac3e41b00157d8761a1834d11540c28566196148b8e74bb70ba52'
assert sha(route / 'completed_input_diagnostic_routed.dcp') == execution['routed_dcp_sha256'] == '0707432cca72c25e71ba35d7fa6968a5cbd413449ca40c425506f9ab56338aaa'
assert sha(route / 'probe.tcl') == '0873675fcec384f676a80b75b746460fbff2ecc3ee162f6111705ead2fad6d4a'
receipt = dict(line.split('=', 1) for line in (route / 'receipt.txt').read_text().splitlines())
assert receipt['deployment_eligible'] == 'false'
for clock, values in {'source_100': (1.758, 0.102), 'island_175': (-8.324, 0.039)}.items():
    for kind, value in zip(('max', 'min'), values):
        assert float(receipt[f'{clock}.{kind}.slack']) == value
        report = (route / f'{clock}_{kind}.rpt').read_text()
        slacks = re.findall(r'^Slack \([^\n]*?\)\s*:\s*(-?\d+\.\d+)ns', report, re.M)
        assert len(slacks) == 20 and float(slacks[0]) == value
timing = (route / 'timing_unqualified.rpt').read_text()
row = re.search(r'^\s*(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$', timing, re.M)
assert row and row.groups() == ('-8.324', '-7913.583', '2309', '12037', '0.039', '0.000', '0', '12037', '1.830', '0.000', '0', '5457')
assert 'Timing constraints are not met.' in timing
for src, dst, setup, hold in [('source_100', 'island_175', '-0.504', '0.145'), ('island_175', 'source_100', '-1.426', '0.073')]:
    match = re.search(r'^' + src + r'\s+' + dst + r'\s+([^\n]+)$', timing, re.M)
    assert match and match[1].split()[0] == setup and match[1].split()[4] == hold
status = (route / 'route_status.rpt').read_text()
assert re.search(r'fully routed nets\.+\s*:\s*7597\s*:', status)
assert re.search(r'nets with routing errors\.+\s*:\s*0\s*:', status)
util = (route / 'utilization.rpt').read_text()
for label, value in [('Slice LUTs', 2592), ('Slice Registers', 5103), ('DSPs', 21), ('RAMB18', 15), ('Unique Control Sets', 75)]:
    assert re.search(r'\|\s+' + re.escape(label) + r'\s*\|\s*' + str(value) + r'\s*\|', util)
commands = [line.strip() for line in (route / 'inherited_constraints.xdc').read_text().splitlines() if line.strip() and not line.lstrip().startswith('#')]
assert commands == ['create_clock -period 10.000 -name source_100 [get_ports clk]', 'create_clock -period 5.714 -name island_175 [get_ports fft_clk]', 'current_instance -quiet']
runner = (route / 'probe.tcl').read_text()
assert not any(token in runner for token in ('set_false_path', 'set_multicycle_path', 'set_clock_groups', 'create_clock', 'read_xdc'))
critical = (route / 'island_175_max.rpt').read_text().split('Slack (VIOLATED)', 2)[1]
for token in ('registered_scheduling.expected_product_metadata_reg[0]/C', 'checked_product_bank.origin_valid_reg/D', '13.941ns', 'logic 4.034ns', 'route 9.907ns', '26  (CARRY4=6 LUT4=2 LUT5=7 LUT6=11)'):
    assert token in critical
cdc = (route / 'cdc_unqualified.rpt').read_text()
for pattern in (r'^CDC-1\s+Critical\s+1\s', r'^CDC-3\s+Info\s+17\s', r'^CDC-15\s+Warning\s+139\s'):
    assert re.search(pattern, cdc, re.M)
assert 'checking no_input_delay (114)' in timing and 'checking no_output_delay (124)' in timing
result = dict(route_complete=True, timing_pass=False, wns_ns=-8.324, tns_ns=-7913.583,
    failing_setup_endpoints=2309, hold_slack_ns=0.039, failing_hold_endpoints=0,
    routed_nets=7597, routing_errors=0, lut=2592, ff=5103, dsp=21, ramb18=15,
    critical_logic_levels=26, critical_data_delay_ns=13.941,
    critical_logic_delay_ns=4.034, critical_routing_delay_ns=9.907,
    routed_critical_cdc=1, cdc_warnings=139, cdc_info=17,
    constraints_unchanged=True, external_io_and_cdc_qualified=False, deployment_eligible=False,
    dcp_sha256=execution['routed_dcp_sha256'])
(root / 'audit.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result))
