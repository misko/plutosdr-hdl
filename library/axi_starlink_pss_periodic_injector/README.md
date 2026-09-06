# Periodic PSS qualification source

This experimental, RX-only IP exists only in the `acquisition-injection`
profile. It is **DO NOT MERGE** and is never eligible for persistent flash.

After software seals exactly 130 CI16 samples, one future-indexed arm replaces
I/Q with that fixture at offsets `0..129` once every 20,000 accepted samples.
All intervening I/Q is the deterministic nonzero floor `I=1,Q=0`, avoiding
zero normalization denominators. The sequence repeats exactly 130 times and
ends at `start + 2,580,129`. Strobe, enable, index, and timestamp remain
source-derived. That interval guarantees at least one wholly deterministic
20,000-by-64 phase map regardless of the phase-map boundary present when
software arms it.

The AXI-Lite ABI at `0x79030000` is:

| Offset | Name | Access | Meaning |
|---:|---|:---:|---|
| `0x00` | identification | R | `0x50535349` (`PSSI`) |
| `0x04` | version | R | `0x00010000` |
| `0x08` | capabilities | R | periodic, deterministic-fill, absolute-index, source-metadata |
| `0x0c` | geometry | R | `{repetitions[15:0], fixture_samples[15:0]}` |
| `0x10` | period | R | 20,000 accepted samples |
| `0x14/18` | current index | R | coherent low-then-high scheduling snapshot |
| `0x1c` | fixture data | W | `{Q[15:0], I[15:0]}` |
| `0x20` | control | W | exactly `1` clear, `2` commit, or `4` arm |
| `0x24/28` | start index | R/W | future absolute accepted-sample start |
| `0x2c` | generation | R/W | nonzero sealed fixture identity |
| `0x30` | status | R | load count and fail-closed lifecycle flags |
| `0x34` | last generation | R | last clean completion identity |
| `0x38` | last repetitions | R | 130 only after clean completion |
| `0x3c/40` | last offset | R | `2,580,129` |

Status bits `7:0` are inflight, mismatch, rejected, completed, active, pending,
arm-ready, and fixture-valid from bit 7 down to bit 0. Bits `15:8` report the
fixture load count. Invalid, late, overlapping, overflowing, or discontinuous
transactions fail closed and latch a sticky error.

Run the exact-geometry self-test with `./run_tests.sh`.
