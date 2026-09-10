"""Root independent raw-boundary/count audit after actual58385 terminal."""
import csv
import hashlib
import json
from pathlib import Path

out=Path(__file__).resolve().parent
prepared=out.parent/'checked-product-actual-prepared-v2'
sim=prepared/'project/exact_control_actual.sim/sim_1/behav/xsim'
old=out.parent/'checked-product-actual-prepared-v1/project/exact_control_actual.sim/sim_1/behav/xsim'
execution=json.loads((out/'outcome.json').read_text())
assert execution['vendor_exit']==execution['result_exit']==0 and execution['functional_accepted']
result=json.loads(json.loads((out/'result-check.json').read_text())['stdout'])
markers=result['final_drain_witnesses']['markers']
assert markers==[[0,32,142157,146711,4554],[1,6,172014,176847,4833]]
wanted={row[3] for row in markers};captured={};total=0;previous=-1
for name in ('fft_bank_owned_trace.csv','exact_control_extra_trace.csv'):
    with (sim/name).open() as stream:
        reader=csv.reader(stream)
        if name=='fft_bank_owned_trace.csv':next(reader)
        for row in reader:
            cycle=int(row[0]);assert len(row)==24 and cycle==previous+1
            previous=cycle;total+=1
            if cycle in wanted:captured[cycle]=row
assert total==624233==result['ownership']['pre']==result['ownership']['post']
for profile,count,forward,drain,service in markers:
    row=captured[drain]
    assert [row[i] for i in (1,2,3,4,8,16,21,22)]==[str(profile+1),str(profile),'1','2','0','0','1','0']
    values=result['service_cycles'][str(profile+1)]
    assert len(values)==count and values[-1]==service and max(values)<=5215
ledger=sim/'checked_product_ownership_trace.csv'
events={1:0,2:0,3:0,4:0};tuple_differences=0;time_differences=0
with ledger.open() as a,(old/ledger.name).open() as b:
    now,before=csv.reader(a),csv.reader(b)
    assert next(now)==next(before)
    for n,p in zip(now,before,strict=True):
        events[int(n[2])]+=1
        tuple_differences+=n[1:]!=p[1:]
        time_differences+=n[0]!=p[0]
for event,key in ((1,'products'),(2,'publications'),(3,'acks'),(4,'core_takes')):
    assert events[event]==result['ownership'][key]
summary={'original_process':58385,'terminal_exit':0,'rows':total,'final_live_drains':markers,
         'service_counts':[32,6],'absolute_cap':5215,'ledger_events':events,
         'ledger_sha256':hashlib.sha256(ledger.read_bytes()).hexdigest(),
         'diagnostic_vs_failed_v1':{'noncycle_tuple_differences':tuple_differences,'cycle_differences':time_differences},
         'scope':'actual FFT functional changed latency; original v1 remains failed; no physical or RX qualification'}
(out/'audit.json').write_text(json.dumps(summary,indent=2))
print(json.dumps(summary,indent=2))
