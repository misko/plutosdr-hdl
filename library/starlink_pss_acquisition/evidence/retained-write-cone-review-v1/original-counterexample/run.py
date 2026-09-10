"""Counterexample probe: delayed private token must not release a guard early."""
import hashlib
import json
from pathlib import Path
import sys

tree = Path('/tmp/starlink-coarse-alternatives.Y3JzOI/high-rate60-paired')
sys.path.insert(0, str(tree))
from tests.starlink_oracle import retained_closed_input_candidate as closed
from tests.starlink_oracle import retained_output_prototype as old
root = Path(__file__).resolve().parent
sources = closed.sources()
top = closed.RTL / 'starlink_pss_fft_retained_output_impl.v'
pins = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
assert hashlib.sha256(top.read_bytes()).hexdigest() == '1d01972d11486772b627a3afdd594f06e41c0f98b830288e93b371af0506ef1e'
text = top.read_text()
prefix, suffix = text.split('  end else begin : registered_scheduling\n')
token = 'if (return_commit_valid && result_destination_ready && !next_inverse)'
assert suffix.count(token) == 1
mutated = prefix + '  end else begin : registered_scheduling\n' + suffix.replace(token, 'if (guard_commit[0] && !next_inverse)', 1)
mutant = root / top.name
mutant.write_text(mutated)
extra = '''
  integer parent_forward_ack_checks=0;
  always @(posedge fft_clk)begin
    if(dut.retained.island.fast_running && dut.retained.island.guard_ack[0])begin
      if(dut.retained.island.product_bank_valid!==1'b1)
        $fatal(1,"parent forward guard ACK before actual product bank publication cycle=%0d committed=%b commit_pulse=%b bank_valid=%b awaiting=%b ready=%b",fast_cycles,
          dut.retained.island.forward_committed,dut.retained.island.guard_commit[0],
          dut.retained.island.product_bank_valid,dut.retained.island.owners[0].result_guard.awaiting_ack,
          dut.retained.island.owners[0].result_guard.mailbox_input_ready);
      parent_forward_ack_checks=parent_forward_ack_checks+1;
    end
  end
  final $display("PARENT_FORWARD_ACK checks=%0d",parent_forward_ack_checks);
'''
bench = closed.composition(1, 1)
assert bench.count('endmodule') == 1
bench = bench.replace('endmodule', extra + 'endmodule')
baseline = old.run_sv(root / 'baseline', bench, sources)
bad_sources = [mutant if p == top else p for p in sources]
bad = old.run_sv(root / 'pulse_only', bench, bad_sources,
    expected_failure='parent forward guard ACK before actual product bank publication')
assert pins == {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
result = dict(scope='scripted composition counterexample, no production edit or actual FFT',
    original_source_unchanged=True, source_pins=pins, baseline=baseline, rejected_pulse_only=bad)
(root / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(dict(baseline_pass=True, pulse_only_rejected=True, output=bad)))
