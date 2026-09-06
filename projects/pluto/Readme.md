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

Select the input geometry independently with
`STARLINK_PSS_RATE_MSPS=15`, `30`, or `60`.  Both settings are compile-time
choices and are printed as `STARLINK_PSS_BUILD_PROFILE` in the Vivado log.

For example:

```sh
make STARLINK_PSS_RATE_MSPS=15 STARLINK_PSS_PROFILE=acquisition-only
```
