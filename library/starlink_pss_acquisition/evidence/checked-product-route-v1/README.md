# Checked-product route v1: original failure evidence

Original root route handle 91981 completed exit 0 in 67.59263178694528 seconds. Timing FAILED: WNS -8.324 ns, TNS -7913.583 ns, 2309 failing setup endpoints; hold +0.039 ns with no hold failures. The checked lane is held and not deployable.

Contents:

- `original/`: byte-identical full terminal owner file tree from `/home/mouse9911/gits/starlink-build-recovery-20260910.vHzUVnBz/checked-route-parent.3lJAqEWe`, including all route products, original execution and independent root audit.
- `source-inputs/`: exact input synthesis DCP and unchanged route Tcl.
- `report.md`: scope, results, source pins and limitations.
- `SHA256SUMS`: complete portable file inventory, excluding only itself.

Check local bytes with `sha256sum -c SHA256SUMS`. Publication also requires the independent Git-object archive checker at the full committed HDL pin, not only filesystem checks. Original scripts retain their original absolute/path-relative execution provenance; do not execute the vendor owner to inspect this archive. No vendor run is part of packaging.

Input DCP: 62ea84c5d09ac3e41b00157d8761a1834d11540c28566196148b8e74bb70ba52
Route Tcl: 0873675fcec384f676a80b75b746460fbff2ecc3ee162f6111705ead2fad6d4a
Routed DCP: 0707432cca72c25e71ba35d7fa6968a5cbd413449ca40c425506f9ab56338aaa

Routed CDC 1 critical / 139 warning / 17 info is distinct from synthesis CDC 13 critical / 139 warning / 5 info. External IO/CDC/full receiver remain unqualified. No runtime changes, retries, promotion or radio actions.
