# Lossless transport repair only

New packaging tests:10 PASS/0.53s, including eight rejection cases and
full actual reconstruction. Neither simulation nor its acceptance changes.
Both reconstructed gzip and WDB also compare byte-for-byte to the retained
original files. The first manual cmp used a mistyped pytest directory
suffix (`reco0` instead of `rec0`) and returned missing-file exit2; the
correct exact-path read-only comparison passes, without changing files.

The actual reconstructed artifacts remain outside the archive under
`/tmp/starlink-completed-input.5EaJuD/wdb-portable-parts-v1/test_actual_full_saved_wdb_rec0/actual-reconstructed/`.
Their complete size/SHA receipt is included here. Portable reconstruction
needs only the standard-library helper, manifest and three chunks.

Run repository tests with:
`python -m pytest -q tests/starlink_oracle/test_wdb_portable_parts.py`.
The copied test source here is archival; run its normal repository path.
All original monolithic files and original unpublished commit refs remain
local; only the oversized gzip's index entry is removed for portability.
