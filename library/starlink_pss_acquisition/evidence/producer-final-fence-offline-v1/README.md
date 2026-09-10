# Producer-final fence offline evidence

Tested FW `61d5ff33c5faff20c4a05540e8efdb08f03c7709`, HDL
`a226dd615db76830928c83253d204deccdff41e8`. Original final process 98534:
26 PASS, 24.56 seconds, exit 0. Root independent 20741: 26 PASS, 24.70 seconds.

`attempts.tgz`: 6,249,953 bytes, SHA256
`afece16943c3491a2e1619830065a99474cd9c79550b1101fa042e481c74a3a8`.
It contains 1,235 files plus an embedded `receipt.json` exactly equal to
`inventory.json`. Every file has a size/hash/original-path entry. The 47 excluded
symlink identities and their original targets are recorded; no original target
was removed. Earlier failures and source snapshots are retained in this package.

Reproduce from the tested FW checkout with nested tested HDL, Python environment
sanitized:

```
env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH /home/mouse9911/gits/pluto-plus-utils/.venv/bin/python -B -m pytest -q -p no:cacheprovider tests/starlink_oracle/test_product_final_fence.py
```

This is fast Icarus conditional guard/mailbox proof and a quiescent stubbed top
shadow, NOT actual FFT/controller reachability or physical/reset qualification.
No old public state or payload masking. Compare authorization only at the actual
mailbox final-write branch; count three nonsampled private differences. Full512
enabled0/1 each: 89,228 checks, 15 sampled finals, sticky-only witness1. Seven
missing-veto mutants reject at the exact sampled assertion. The source report is
`docs/starlink-producer-final-fence-offline-20260910.md` in the FW repository.
