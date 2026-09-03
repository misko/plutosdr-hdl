# Experimental 15/30/60 MS/s continuous acquisition IP

This IP is restricted to `codex/starlink-rx-only-do-not-merge`. It combines
the independently tested 128-entry loss-detecting RX CDC, continuous shared-
XFFT timing-score and phase-map path, acquisition-health epoch, and PSMA AXI
bridge. The detector always runs at canonical 15 MS/s: source rate 15 bypasses
the conditioner, 30 uses one fixed x2 DDC, and 60 uses two cascaded x2 DDCs.
RX DMA and sparse tracking remain at the selected full source rate.

The sample side is a read-only tap: there is intentionally no ready signal and
therefore no path by which acquisition can stall RX DMA. `sample_strobe` and
`sample_enable` qualify an accepted CI16/index beat; `sample_gap` permits an
upstream source to force a clean overlap-history restart. Any FIFO-full loss is
counted and the recovered stream is gap tagged by the CDC itself.

The AXI clock is also the fixed 100 MHz acquisition clock. The wrapper uses a
single-clock PSMA 1.1 bridge so it does not synthesize redundant asynchronous
mailbox payloads between identical clocks; the separately packaged generic
phase-map bridge retains its independent-clock CDC implementation. Software
must validate the rate-specific PSMA ABI (1.1/1.2/1.3), then explicitly enable
acquisition. The IRQ is
level-based while either immutable phase-map bank is ready.

This package does not by itself prove full-shell fit, timing closure, a built
image, radio behavior, live PSS, or frame alignment.
