# Source-specific checked-product actual run preparation

Offline only:171PASS34.75s, original37746 terminal0. Prior41267 and65253
terminated0 with66 and78PASS. No vendor execution or runtime changes.

`final171.tar.gz` preserves the complete original pytest root, raw log/XML,
prepared84-member source freeze (plus manifest), compiled actor-only source
snapshots, all admission/parser negatives, synthetic numerical/cycle fixtures
and mocked Tcl logs. `earlier66-78.tar.gz` preserves both earlier full attempts.
Synthetic parser fixtures are NOT actual or FFT results. Mock Tcl never creates
a real project or executes the IP factory/vendor. Original directories remain.

`run-preparation-report.md` documents source identity, literal old-runner
inverse, inherited scope and proposed root-owned one-shot invocation. The
prepared84-manifest9b21ff51 is independently checked; no project exists there.
`source-binding.json` records exact tested source and runtime hashes.

SHA256SUMS covers every portable member except itself. Git-object validation
is publication-integrity only, not test/vendor/timing/RF qualification. Extract
tar files into a new directory only; do not overwrite existing evidence.
