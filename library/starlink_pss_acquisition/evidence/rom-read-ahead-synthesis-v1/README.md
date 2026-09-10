# C1 plus K1/M1: completed synthesis, not a timing or release pass

Original handle11476 exited0, 2026-09-10 13:35:46.005660 through
13:37:57.844715 UTC,131.8389s. Owner before/tool/after/overall statuses all0;
all eight nonempty products and their exact lengths/hashes independently pass.
All13 source/generated-wrapper rows and the actual simulation log match;
frozen helper independently replays complete prepared/copied/actual admission.
The18-file prepared inventory remainsd4d364427c31531358ce747b5931d4fa441e8e46002bf986626c69e923be2a39.
Runtime unchanged from accepted actual10102, explicit R/D/S/C/K/M all1.

Synthesized xc7z010clg400-1 maps2059 LUT (1871 logic,188 SRL),4607 FF,
15 RAMB18 (7.5 tiles),21 DSP,7 F7 mux,0 F8/black boxes/latches.
Old C1 synthesis1986 LUT/4500 FF has the same BRAM/DSP counts: +73 LUT/+107 FF.
Kernel hierarchy71 LUT/224 FF becomes114 LUT/331 FF; other hierarchy LUT
allocations also change during optimization/combining. Do not attribute the
entire total LUT delta to the kernel or compare synthesized counts as routed.

DCP2181849bytes,264b7dbb89ccef59b1b41dbaee2e01d4138b8d9a368f64ebc6532efd04f5405e.
Actual propagated clocks source_100=10ns onclk and island_175=5.714000225ns
onfft_clk. CDC17 info/139 warning,0 critical; mailbox CDC and114 input/124
output ports lacking IO delay remain unqualified. No unconstrained internal
endpoint, but no achieved-frequency, placed-slice, setup/hold or receiver claim.
Synth8-7052 reports the speculative-word BRAM cannot absorb its optional
output register; a remaining data path may still limit physical timing.

The archive preserves73 selected original files byte-for-byte plus complete
original-run file identities. It includes every required product, original
owner logs/receipts, source copies/prepared recipe, generated synth wrapper,
IP configuration, synthesis logs/scripts/reports and baseline comparison.
Uncopied project caches/netlists remain intact at original non-/tmp paths;
their identities are recorded, not claimed to be portable payloads here.
No artifacts are reconstructed or relabeled as successful.

Route proposal is independently whole-source-inverted to the reviewed prior
owner using only four exact path/SHA substitutions. Its later authorized
original87839 runs separately; this synthesis snapshot contains no route result.
No retries, constraint changes, radio operation or promotion.
