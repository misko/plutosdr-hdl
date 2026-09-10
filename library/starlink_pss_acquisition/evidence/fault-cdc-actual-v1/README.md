# Single actual C1 run: immutable terminal evidence

Original20091 terminal0, post-source audit0;580.44s. Frozen independent
verify_result33930 terminal0. Source FW4d59ce832/HDL597a8ab65, runtime02de.
All48 prepared source hashes remained exact, inventory9c81c43d….

CDC712146 comparisons passed against the scalar shift of actual fast_fault.
Full main CSVs589950 lines/25ab9d06…; full extra CSVs33180 lines/b965d126…,
all identical to passing111 history. Independent reference remains dec20.
Qualified status1246258=953795 raw-equal+292463 invalid-only; NOT raw217 pass.
115 final-index fault samples and4265 private-reset-low samples are edge
counts, not distinct injections. Original extra final fault count remains2.

Complete gzip logs/CSVs preserve raw byte identities in
raw-artifact-identities.json. Three WDB parts are<=40MiB each; reconstruct
only into a new directory using reconstruct_wdb_parts.py and
simulation/wdb-parts.json. Full original and assembled hashes are in that
manifest; packaging/actual-reconstruction-receipt.json proves successful
actual reconstruction. The helper is byte-identical to the earlier tested
portable helper; no additional simulation was involved.

This is simulation evidence, not CDC/timing closure, physical release or RF
evidence. Prior failed route/source archives remain intact. Manifest-exact
force-add and Git-object verification are required before publication.
