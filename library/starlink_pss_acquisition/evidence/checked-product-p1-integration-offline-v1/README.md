# Checked product P1 offline integration evidence

Tested source FW ed1d85745779e2ac9d324efdb6ed2618569edd76 /
HDL 65cff8a983b2fd8489634939c363f2de230fc512. No vendor or physical run.

Original16693:3304PASS135.97s, then original18575:554PASS57.77s after
test-only distinct-payload rows. These are two exact terminal scopes, not an
invented owner3306 receipt. All five runtime files stayed unchanged.

`retained-attempts.tar.gz` preserves the complete earlier runs/failures,
including the initial3300-pass snapshot. `final-3304.tar.gz` preserves the
original3304 run and paused-fast capacity/rejoin evidence.
`distinct-reset-554.tar.gz` preserves the final554-case integration replay,
including every compiled snapshot, command, log and generated expected file.
All originals remain at the persistent recovery paths recorded in report.md;
no project or failed source snapshot was overwritten. Each archive is under
40MiB. Pytest-created current symlinks are preserved as historical links;
the actual case directories and regular files are included in full.

The raw log/XML copies provide compact terminal inspection. terminal-audit.json
records the exact source/graph/compiled-manifest verification. SHA256SUMS binds
all portable members. Repository/history at the tested pins is the source
replay prerequisite; this archive is not a standalone replacement git history.

Important limitations: identity/control actor, not FFT numerics; +8 measured
actor clocks, not real service/timing closure; backpressurable reset recovery,
not guaranteed512-word capture while fast is paused or uninterrupted ADC;
no arbitrary paused-fast old inverse-output-owner reset guarantee. See the
full report and explicit negative-control chronology.
