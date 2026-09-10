# Combined exact-control actual run: qualified scope passes

One actual175 run, original handle79656 terminal0. Measured
FW6a8bce26b7ecc408a610efc139b60fb0d3c97414 /
HDL5c18664368eeaf1bf2f76a2a672dfbd3f78c167f; tested preparation
FW9135a11738afb5f6553d979b20d606e6af0a1d00 /
HDLca0117ccef655f189612769d21e109a20e64d364. Exact seven runtime modules
remain ae50. Candidate R1/D1/S1; independent dec20 reference R1, no D/S
implementation. Both extras1/FAST175/QUICK0, Vivado2022.2/two threads.

Original directory `/tmp/starlink-completed-input.5EaJuD/extra-edge-combined-prepared-v1`.
Inventory8e9251fe06e41917e9e0b5ebceef36db444bc39770efe7acb940dbfcc4ed7906
passes before/after. Runner496a3ed4... unchanged. Start08:40:10UTC,
exit08:50:04UTC, wall593.59s, user609.66/system8.99s, peak RSS1132592KB.
All27 warnings equal the baseline after normalizing only output paths;
no waiver. Simulator finishes at3560734467751fs, no fatal/retry.

Both complete original main CSVs:589950lines, byte equal and historical
25ab9d06ca0e03f280540cda625a7826b3c4cbaa6322ce3266c59e1fbad94122.
Both extra CSVs:33180lines, byte equal,
b965d12603a64111fa9c6ea36cb0f12189945ad4d9be7cf4fbd883980c4ec4a0.
No new main golden or assumed historical extra golden was introduced.

Literal runner receipt/golden gates pass. Both extra tasks independently
assert2finalfaults/3heldstalls/2one-sidedresets/4recoveries. Final candidate
shadow:1246258checks,780367active,36consumedidentities,270private scratch
differences,2finalfaultedges,99936ownedstalls,143reset-ownededges. Scratch
differences are permitted only while unconsumed by the unchanged observer;
all consumed identities match. This is tested trace equivalence, not a
universal proof or attribution to either knob separately.

Both original registered receipts retain84preflightreason cases,
12active-inputfault cases,12expected-cache cases,84rawbank boundary rows,
8scheduler boundary faults/4boundary resets,106completion receipts,
44healthyblocks and4548maximum nominal forward interval cycles.
Retirement shadow1179897checks; actual inverse_current and sticky_forward
remain0, so no coverage of those two forced-fault categories is inferred.

Independent frozen qualified-observer audit also passes:
1246258samples=953795raw-equal+292463invalid-only. All differing rows
explicitly have both valid bits0. Full four-state categories are:

| Candidate | Reference | Rows |
| --- | --- | ---: |
| `x1x00101` | `00000101` | 148 |
| `x1x00000` | `11z00000` | 99179 |
| `zzz00000` | `00000000` | 193136 |

First1200640062032fs, last2811131571128fs. Full per-epoch counts and every
raw row are retained, not capped to baseline29. Driver origin remains
unknown. All216 other fields remain exact unconditionally; all8status
bits remain exact whenever either valid is not exactly0. This is NOT an
original raw217 pass, and no prior strict/qualified failure is erased.

All sources, timing/warnings, raw logs/rows, exact terminal receipts,
independent observer audit, full CSVs and WDB are archived. Large raw logs
and CSV are losslessly gzip-compressed; compressed-original-sha256.txt
pins every raw input, with decompression verified. Original project remains.

## Portable WDB packaging

The original gzip is105807603bytes, above a100MiB hosting limit. It remains
intact locally at its original archive path but is excluded from the tracked
portable inventory. The original uncompressed WDB/project also remain intact.
Three tracked ordered chunks are41943040/41943040/21921523bytes, each<=40MiB.
`simulation/wdb-parts.json` records every part SHA/size, the assembled gzip
SHA/size and original WDB SHA/size. No LFS or remote rewrite is needed.

The original unpublished archive commits are preserved in BOTH repositories
under LOCAL-ONLY ref `refs/local-only/exact-control-combined-oversized-20260910`:
HDL67795ad300d9480d539fc6ad05ebb02330088aa3 /
FWa1707a594a0b4f481e491ca820f77eb6c0ec11df. Do not push those backup refs.
Only the two own unpublished archive/report tips are amended for portability.
The original72-entry inventory (sha256e908dac9...) and original README are
retained as `original-oversized-SHA256SUMS` and `original-oversized-README.md`.

After verifying the portable SHA256SUMS, reconstruct into a NEW directory:

```sh
python3 reconstruct_wdb_parts.py --manifest simulation/wdb-parts.json --output-dir /absolute/new/reconstructed-wdb
```

Existing output directories are rejected. Missing, reordered, corrupt,
oversized or unsafe-path parts are rejected; both assembled gzip and raw
WDB size/SHA must match. Failures retain any newly created partial output
for inspection; the helper never removes or overwrites existing data.
Packaging tests and a full actual reconstruction are retained in `packaging/`.
This changes only evidence transport, not simulation, source or acceptance.

No attribution run, synthesis, route, arithmetic graft, RF test, production
change or promotion was performed. The old synthesis script only forwards
REGISTERED_SCHEDULING and requires scope.txt: it must NOT be directly used
on this freeze. A separately reviewed offline adapter must explicitly bind
all R/D/S and close exactly the seven tested runtime sources before any
future source-specific physical authorization.
