# Testing suspend

How a build with `TARGET_SUPPORTS_SUSPEND := true` is tested before suspend may be enabled in a release
(the gate in `updating.md`). Kernel r14 or later: it has the CPU idle states and the mdp5 fix; r12
suspends once, then the next suspend fails in `mdp5_pipe_release` and the audio DSP stops answering.

Baseline to beat, release of 2026-09-21 without suspend: **1.7 % per hour** screen off, Wi-Fi on
(27 hours from full to 54 %).

## Tools

- `tools/suspend-report.sh`, on the tablet as root: suspend successes and failures (and the step and
  device of the last failure), the last wake-up interrupt, CPU idle states in use, RPM statistics (did
  the SoC power down, not only the CPUs), the wake sources and wake locks that kept it awake, and
  whether display, touch, Wi-Fi and the remote processors are back after a resume.
- `tools/battery-history.py`, on the computer: drain per plugged/unplugged period with the screen-on
  time, from `adb shell dumpsys batterystats --history`.

## Steps

1. Flash `vendor` and `product` of the test build and start its boot image from RAM
   (`fastboot boot`): nothing is written to BOOT until the build has passed. On a failure, a restart
   brings back the installed release.
2. **Suspend at all.** Screen off, wait three minutes, screen on with the power key. `suspend-report.sh`:
   `success` has grown, `fail` is 0. A USB cable can keep the USB controller awake: if nothing
   suspends, repeat unplugged and read the report afterwards.
3. **Wake-ups.** Power key: the screen comes on within about two seconds and touch works. An alarm set
   in the Clock app three minutes ahead rings on time with the screen off. Repeat both five times.
4. **Everything back after a resume**, after the repeated wake-ups: Wi-Fi reconnects, a sound plays on
   the speakers and on headphones, both cameras open, the report counts no `Some devices failed to
   suspend`, `mdp5_pipe_release`, `AFE enable for port` or GPU faults.
5. **Standby drain.** Charge to 100 %, unplug, screen off, Wi-Fi on, leave it overnight. Then
   `dumpsys batterystats --history` into `battery-history.py`: the unplugged, screen-off period is the
   result. Compare with the baseline above, and look at the RPM statistics in the report: if the CPUs
   power down but the SoC never does (no XO shutdown), the next step is in the kernel (clock votes).
6. **GNSS separately**: the modem DSP stays off unless `persist.vendor.gtowifi.gnss` is 1. Its cost is
   a second overnight measurement with it on.

## Passed means

Steps 2 to 4 without a single failure, and a standby drain clearly below the baseline. Then suspend may
be enabled in a release, with the kernel revision and the measured drain in the release notes.
