#!/system/bin/sh
#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# What the kernel and Android say about suspend since boot, and whether the hardware came back. Run as root
# on the tablet:
#
#     adb root && adb push tools/suspend-report.sh /data/local/tmp/ && adb shell sh /data/local/tmp/suspend-report.sh
#
# Needs a kernel with PM_SLEEP_DEBUG and QCOM_RPM_MASTER_STATS for everything (kconfigs/fixups.config).

mountpoint -q /sys/kernel/debug 2>/dev/null || mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null

section() { echo; echo "== $*"; }

section "uptime, battery"
uptime
b=/sys/class/power_supply/pmi632-battery
echo "battery $(cat $b/capacity 2>/dev/null)% $(cat $b/status 2>/dev/null), current $(cat $b/current_now 2>/dev/null) uA"

section "suspend statistics (/sys/power/suspend_stats)"
for f in /sys/power/suspend_stats/*; do
    [ -f "$f" ] && printf '%-24s %s\n' "$(basename "$f")" "$(tr '\n' ' ' < "$f")"
done
echo "mem_sleep: $(cat /sys/power/mem_sleep 2>/dev/null)   last wakeup irq: $(cat /sys/power/pm_wakeup_irq 2>/dev/null || echo -)"

section "CPU idle states: name usage time(s)"
for c in /sys/devices/system/cpu/cpu[0-9]*; do
    [ -d "$c/cpuidle" ] || { echo "$(basename "$c"): no cpuidle"; continue; }
    line="$(basename "$c"):"
    for s in "$c"/cpuidle/state*; do
        line="$line $(cat "$s/name") $(cat "$s/usage") $(( $(cat "$s/time") / 1000000 ));"
    done
    echo "$line"
done

section "power domains (the CPU cluster and system domains go off when the SoC powers down)"
# domain rows start in the first column, the devices of a domain are indented
grep -v -E "^ |^domain|^---" /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null | awk '{ print $1, $2 }' | head -24

section "RPM: did the SoC power down? (vmin/vlow counters, per-master shutdowns)"
found=0
for d in /sys/kernel/debug/qcom_stats /sys/kernel/debug/qcom_rpm_master_stats; do
    [ -d "$d" ] || continue
    found=1
    for f in "$d"/*; do echo "-- $(basename "$d")/$(basename "$f")"; head -8 "$f" 2>/dev/null; done
done
[ $found = 1 ] || echo "no RPM statistics (kernel before r14, or without QCOM_STATS / QCOM_RPM_MASTER_STATS)"
echo "-- suspend durations (sleep_time)"; head -12 /sys/kernel/debug/sleep_time 2>/dev/null

section "wakeup sources (name active_count wakeup_count total_ms prevent_suspend_ms), most suspend-preventing first"
awk -F '\t+' 'NR > 1 { print $1, $2, $4, $7, $10 }' /sys/kernel/debug/wakeup_sources 2>/dev/null | sort -k5,5nr -k4,4nr | head -12

section "Android wake locks, longest held"
dumpsys suspend_control_internal 2>/dev/null | grep -i -E "wakelock|name" | head -12

section "after resume: display, touch, Wi-Fi, remote processors"
dumpsys power 2>/dev/null | grep -m1 mWakefulness
echo "backlight $(cat /sys/class/backlight/backlight/brightness 2>/dev/null)"
getevent -lp 2>/dev/null | grep -m1 -i "ft5x06" || echo "touch device MISSING"
cmd wifi status 2>/dev/null | grep -m1 -i -E "connected to|disconnected|not connected"
for r in /sys/class/remoteproc/*; do echo "$(cat "$r/name"): $(cat "$r/state")"; done

section "kernel complaints since boot (counts)"
dmesg > /data/local/tmp/.suspend-report-dmesg 2>/dev/null
for p in "PM: suspend entry" "PM: suspend exit" "Some devices failed to suspend" "mdp5_pipe_release" \
         "AFE enable for port" "gpu fault" "hangcheck detected gpu lockup" "failed to resume" "Freezing of tasks failed"; do
    printf '%-34s %s\n' "$p" "$(grep -c "$p" /data/local/tmp/.suspend-report-dmesg)"
done
rm -f /data/local/tmp/.suspend-report-dmesg
