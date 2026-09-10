# Original23845: incomplete actual ROM evaluation

The one authorized C1+K1/M1 vendor evaluation terminated1 on a waveform disk
quota error at epoch160. This is neither a passing actual test nor a functional
counterexample. There was no retry, source edit or physical run.

Both partial main CSVs contain34373632 bytes and569129 newline characters,
SHA5963a605e4da325207d6672939b38b0c9b49a28fbd70f82652adcbb85a9735a2.
They match each other and exact prefixes of the passing C1 files, but end
mid-line. Extra CSVs do not exist. All292463 logged invalid-only status rows
are retained; no complete ROM/exact-control/qualified-status terminal exists.

Original zero-byte post-run/time/status files are retained literally. Their
failed stored before/after hash comparison is not repaired. Fresh read-only
verification passes all56 frozen files, the exact6f5eddb9 inventory and the
9f198abf runner; fresh hashes equal original before.sha256. Frozen verify_result
rejects the incomplete run. See fresh-read-only-audit.json and the explicitly
labeled tool-response transcription, not fabricated original receipt values.

Raw logs/partial CSVs are losslessly gzip-compressed; their original byte
identities are recorded. Generated IP was absent before project creation;
19 generated .xci/.vhd files and a fresh after-failure inventory are included.
The original owner after-IP receipt remains empty. No precompile IP comparison
is claimed. Complete prepared source/settings and original owner are included.

The partial WDB is preserved exactly, not claimed to be a healthy waveform:
119349248 bytes, SHAe50d813dd2ecb344f013bbb469c8f63047dec90a669903a582e856666d826e57.
Its gzip is108587229 bytes,
SHA723fdc2da9f2c330b3b6d4ff71ce38d1c6a70a0158b7dec85c9a39d3192b7831.
Reconstruct the three <=40MiB parts only into a new directory with the
unchanged previously tested reconstruct_wdb_parts.py and
simulation/wdb-parts.json. The reconstruction receipt proves byte identity,
not waveform semantic validity. Originals and the monolithic gzip remain on
disk outside this portable package; no oversized monolithic Git blob is used.

Packaging/staging occurred only under the authorized non-/tmp recovery parent
after storage recovery. No original failure artifact was modified or deleted.
The manifest must be checked from Git objects as well as the local filesystem.
