# PLUTO HDL Project

Here are some pointers to help you:
  * [Board Product Page](https://www.analog.com/adalm-pluto)
  * [Board Product Page](https://www.analog.com/cn0566)
  * Parts : [RF Agile Transceiver](https://www.analog.com/ad9363)
  * Project Doc: https://wiki.analog.com/university/tools/pluto	
  * Project Doc: https://wiki.analog.com/resources/eval/user-guides/circuits-from-the-lab/cn0566
  * HDL Doc: https://wiki.analog.com/resources/eval/user-guides/ad-fmcomms2-ebz/reference_hdl
  * Linux Drivers: https://wiki.analog.com/resources/tools-software/linux-drivers/iio-transceiver/ad9361

## Experimental PSS build profiles

`STARLINK_PSS_PROFILE=full` is the default and retains the scheduled tracker,
its injection/telemetry boundary, continuous acquisition, and RX DMA.  The
staged blind-acquisition image uses
`STARLINK_PSS_PROFILE=acquisition-only`; it omits the tracker IP, AXI aperture,
and interrupt, and fans the unmodified RX0 CI16 stream directly to both the
continuous acquisition engine and RX DMA.  The acquisition engine remains
independent of the IIO scan-enable mask in either profile.

`STARLINK_PSS_PROFILE=acquisition-injection` is the M2 qualification image. It
retains the acquisition-only resource shape and adds a bounded PSSI peripheral
at `0x79030000`. PSSI can substitute one sealed 130-sample CI16 fixture every
20,000 accepted samples for exactly 130 repetitions while leaving all source
indices and timestamps intact. This profile fails the build unless the selected
rate is exactly 15 MS/s; it is RAM-boot-only and must never be persistently
flashed.

Select the input geometry independently with
`STARLINK_PSS_RATE_MSPS=15`, `30`, or `60`.  Both settings are compile-time
choices and are printed as `STARLINK_PSS_BUILD_PROFILE` in the Vivado log.

For example:

```sh
make STARLINK_PSS_RATE_MSPS=15 STARLINK_PSS_PROFILE=acquisition-only
make STARLINK_PSS_RATE_MSPS=15 STARLINK_PSS_PROFILE=acquisition-injection
```
