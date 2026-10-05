#!/bin/bash
# On the build host: start (or re-enter) the LineageOS build container.
#   ./run-container.sh                 interactive shell
#   ./run-container.sh <command...>    run one command, e.g. ./run-container.sh payload/build-host/sync-and-build.sh sync
#   DETACH=1 NAME=lineage-sync ./run-container.sh <command...>   same, detached, logged to $BASE/logs/$NAME.log
#
# Isolation on a shared host: nothing is installed on the host; source, ccache and output live under
# $BASE (default ~/lineage); memory is not capped by default (MEM=none: a 16 GB host has to swap; set MEM,
# e.g. 96g, on a shared machine); CPUs are
# whatever the host leaves to ordinary processes (CPUs it isolates with isolcpus are never used).
set -euo pipefail
BASE=${BASE:-$HOME/lineage}
IMAGE=${IMAGE:-lineage-build}
NAME=${NAME:-lineage-build}
MEM=${MEM:-none}
DOCKER=${DOCKER:-sudo -n docker}
if [ -z "${CPUS:-}" ] && [ -s /sys/devices/system/cpu/isolated ]; then
	# everything except the cores the host isolates for its own real-time work
	CPUS=$(python3 - <<'PY'
import os
iso = set()
for part in open('/sys/devices/system/cpu/isolated').read().strip().split(','):
    if part:
        a, _, b = part.partition('-')
        iso.update(range(int(a), int(b or a) + 1))
print(','.join(str(c) for c in range(os.cpu_count()) if c not in iso))
PY
)
fi
args=(--rm --name "$NAME" --hostname lineage-build
	-v "$BASE/android:/home/build/android" -v "$BASE/ccache:/home/build/.ccache"
	-v "$BASE/payload:/home/build/payload"
	-e LINEAGE_DIR=/home/build/android/lineage -e PAYLOAD_DIR=/home/build/payload
	-e CCACHE_DIR=/home/build/.ccache
	--oom-score-adj -500)
# Out of memory, the kernel kills the host's other programs before the build: build 31d lost soong_build
# while a browser ran (a dedicated host loses nothing by this)
# MEM=none: no cap, so that the container may use the host's swap (a laptop with 16 GB RAM and zram);
# a cap with --memory-swap equal to it means no swap at all
[ "$MEM" = none ] || args+=(--memory "$MEM" --memory-swap "$MEM")
[ -z "${BUILD_JOBS:-}" ] || args+=(-e BUILD_JOBS="$BUILD_JOBS")
[ -n "${CPUS:-}" ] && args+=(--cpuset-cpus "$CPUS")
if [ $# -eq 0 ]; then
	exec $DOCKER run -it "${args[@]}" "$IMAGE" bash -l
elif [ "${DETACH:-0}" = 1 ]; then
	# long jobs: survive the SSH session. Output goes to $BASE/logs/<name>.log, last line JOB_RC=<status>
	mkdir -p "$BASE/logs"
	$DOCKER run -d "${args[@]}" -v "$BASE/logs:/home/build/logs" "$IMAGE" \
		bash -lc "( $* ) > /home/build/logs/$NAME.log 2>&1; echo JOB_RC=\$? >> /home/build/logs/$NAME.log"
	echo "started container $NAME; follow with: tail -f $BASE/logs/$NAME.log"
else
	exec $DOCKER run "${args[@]}" "$IMAGE" bash -lc "$*"
fi
