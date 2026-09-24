#!/vendor/bin/sh
#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Start the remote file system server of the modem DSP, which then starts the modem (rmtfs -s), but
# only when this kernel has the modem: without it rmtfs would exit and be restarted for ever.
# The outcome goes to vendor.gtowifi.modem.state (off, absent, unbound or bound); init starts rmtfs
# when it is "bound" (init.gtowifi.rc). "probing" first, so that a second run changes the property
# again: switching GNSS off stops rmtfs but leaves the state at "bound".

DEVICE=/sys/bus/platform/devices/4080000.remoteproc
BOUND=/sys/bus/platform/drivers/qcom-q6v5-mss/4080000.remoteproc

setprop vendor.gtowifi.modem.state probing

# The modem DSP runs for as long as it is started, whether anybody wants a position or not; it is off
# unless persist.vendor.gtowifi.gnss is 1 (setprop persist.vendor.gtowifi.gnss 1 switches it on, now
# and at every boot; 0 stops it again)
if [ "$(getprop persist.vendor.gtowifi.gnss)" != 1 ]; then
    echo "init.gtowifi.modem.sh: GNSS is off (persist.vendor.gtowifi.gnss != 1)" > /dev/kmsg
    setprop vendor.gtowifi.modem.state off
    exit 0
fi

if [ ! -e "$DEVICE" ]; then
    echo "init.gtowifi.modem.sh: no modem in this kernel's device tree, GNSS stays off" > /dev/kmsg
    setprop vendor.gtowifi.modem.state absent
    exit 0
fi

# The driver probes late: it waits for its regulators, clocks and reserved memory
i=0
while [ ! -e "$BOUND" ] && [ $i -lt 60 ]; do
    sleep 1
    i=$((i + 1))
done

if [ -e "$BOUND" ]; then
    echo "init.gtowifi.modem.sh: modem driver bound after ${i} s, starting rmtfs" > /dev/kmsg
    setprop vendor.gtowifi.modem.state bound
else
    echo "init.gtowifi.modem.sh: the modem driver did not bind, GNSS stays off" > /dev/kmsg
    setprop vendor.gtowifi.modem.state unbound
fi
