#!/vendor/bin/sh
#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Start the remote file system server of the modem DSP, which then starts the modem (rmtfs -s), but
# only when this kernel has the modem: without it rmtfs would exit and be restarted for ever.
# The outcome goes to vendor.gtowifi.modem.state; init starts rmtfs when it is "bound"
# (init.gtowifi.rc). "probing" first, so that a second run changes the property again.

DEVICE=/sys/bus/platform/devices/4080000.remoteproc
BOUND=/sys/bus/platform/drivers/qcom-q6v5-mss/4080000.remoteproc

setprop vendor.gtowifi.modem.state probing

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
