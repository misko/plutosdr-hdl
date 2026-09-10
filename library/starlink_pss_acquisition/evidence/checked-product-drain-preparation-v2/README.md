# Checked-product drain preparation v2 — offline only

This archive preserves the approved bench-only successor preparation and all
owner test attempts. It does not relabel original actual30484, whose outcome
and original result-check exception remain FAIL. No vendor/physical execution
was performed for this successor by the source owner.

The original84-source archive excludes only its generated `project` directory;
the original project, full CSVs/logs/WDB and root-owned failure evidence remain
untouched at the persistent recovery paths recorded in report.md. It is not a
complete archive of actual30484. The89-source successor bundle is complete and
has no project. Its inventory SHA is
55288860074df8107d142c97bd69cb67bc71815f13bbb8bacc3b664b9547f5ea.

Preserved attempts:

- scheduler-v1-v2.tar.gz: original30PASS0.28s and expanded35PASS0.30s, including
  raw executed expected-failure mutant logs and VVP/fixture sources.
- preparation-tests76.tar.gz: original76PASS0.58s (41 preparation/receipt plus35
  scheduler), complete original pytest tree, stdout, XML and generated snapshots.
- prepared89.tar.gz: exact source-specific successor freeze; full inverse of
  the two altered inherited files restores every original84 source hash.
- original84-failed-run-source.tar.gz: literal prior source-only freeze, manifest
  9b21ff51490f0deb87ae0b69a78e65e37895bb8006f67b2615a567e70e8e63c7.

The four new policy/test sources, unchanged imported clean_env source, and the
reviewed report are also copied directly for review. Root independently ran
35PASS0.34s at checked-drain-parent.FkKDoLe7 and then76PASS0.46s at
checked-drain-prep-parent.TQPsrJdl, confirming34 live and89 prepared hashes
unchanged. Those independent root trees are not copied into this owner archive.

Runtime14, factory, vectors, original a04c result parser and all original
fault/numerical/source observers are unchanged. The new helper first executes
the old32/6/5215 full-result gate and only then validates the two drain receipts
against actual live CSV rows and final service values. No raw217, physical or
radio qualification is asserted. The separate physical draft remains outside
this package and rejects the failed original actual outcome.

Verify SHA256SUMS before extracting any tar into a new empty directory. Tests
are source-specific to the original repository/recovery paths documented in
report.md; archived snapshots preserve evidence, not a path-independent vendor
launcher. Publication is to the existing do-not-merge ROM-prefetch branches only.
