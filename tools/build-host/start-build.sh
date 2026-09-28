#!/bin/bash
# On the workstation: ship the payload made by make-payload.sh to the build host and start a detached build
# (by default sources -> patches -> build). Refuses to run while another lineage container is up,
# because the scripts under $BASE/payload must not change under a running job.
#   . my-host.env; NAME=lineage-build3 ./start-build.sh
# Follow it with:  ssh $HOST tail -f $BASE/logs/$NAME.log     (ends with BUILD_RC= and JOB_RC=)
#
# The host is described by environment variables, best kept in an env file per host (see
# host.env.example): HOST (ssh destination, required), BASE (where tree, ccache and output live,
# default /mnt/lineage), REQUIRE_MOUNT (1: BASE must be a mounted file system), MEM (container memory
# cap, or none), BUILD_JOBS (parallel build jobs; unset = all threads), INHIBIT (1: keep the host awake).
# STEPS: the sync-and-build.sh steps to run, default "sources patches build"; a new host needs
# "sync sources patches build" (the sync alone is a download of well over 100 GB).
# The container image is built from the payload's Dockerfile when the host does not have it yet.
# INHIBIT=1 keeps the host from sleeping for as long as the container runs (systemd-inhibit).
set -euo pipefail
HOST=${HOST:?set HOST (ssh destination of the build host), e.g. from an env file}
BASE=${BASE:-/mnt/lineage}
REQUIRE_MOUNT=${REQUIRE_MOUNT:-1}
NAME=${NAME:-lineage-build3}
STEPS=${STEPS:-sources patches build}
MEM=${MEM:-96g}
BUILD_JOBS=${BUILD_JOBS:-}
INHIBIT=${INHIBIT:-0}
IMAGE=${IMAGE:-lineage-build}
HERE=$(cd "$(dirname "$0")" && pwd)
PAYLOAD=${PAYLOAD:-$HERE/gtowifi-mainline-payload.tar.gz}
SSH="ssh -o BatchMode=yes -o ConnectTimeout=15"

[ -f "$PAYLOAD" ] || { echo "run make-payload.sh first" >&2; exit 1; }
if [ "$REQUIRE_MOUNT" = 1 ]; then
	$SSH "$HOST" "mountpoint -q $BASE" || { echo "$BASE is not mounted on $HOST (or the host is unreachable)" >&2; exit 1; }
else
	$SSH "$HOST" "test -d $BASE" || { echo "$BASE does not exist on $HOST (or the host is unreachable)" >&2; exit 1; }
fi
running=$($SSH "$HOST" 'sudo -n docker ps --format "{{.Names}}"' | grep '^lineage-' || true)
[ -z "$running" ] || { echo "a lineage container is already running: $running" >&2; exit 1; }

# The bind-mounted directories must exist before docker would create them owned by root
$SSH "$HOST" "mkdir -p $BASE/android $BASE/ccache $BASE/payload $BASE/logs"
scp -q -o BatchMode=yes "$PAYLOAD" "$HOST":"$BASE"/gtowifi-mainline-payload.tar.gz
echo "SCP_RC=$?"
$SSH "$HOST" "set -e; cd $BASE/payload; rm -rf android_device_samsung_gtowifi_mainline; tar xzf ../gtowifi-mainline-payload.tar.gz; git -C android_device_samsung_gtowifi_mainline log --oneline -1; ls kernel"

if ! $SSH "$HOST" "sudo -n docker image inspect $IMAGE >/dev/null 2>&1"; then
	echo "building the container image $IMAGE on $HOST ..."
	$SSH "$HOST" "cd $BASE/payload/build-host && sudo -n docker build -q -t $IMAGE ." | tail -2
fi

cmd=
for step in $STEPS; do
	cmd="$cmd${cmd:+ && }payload/build-host/sync-and-build.sh $step"
done
$SSH "$HOST" "cd $BASE/payload/build-host && BASE=$BASE MEM=$MEM BUILD_JOBS=$BUILD_JOBS IMAGE=$IMAGE DETACH=1 NAME=$NAME ./run-container.sh '$cmd'"
echo "START_RC=$?"

if [ "$INHIBIT" = 1 ]; then
	# held until the container ends; the host sleeps as usual afterwards
	$SSH "$HOST" "nohup systemd-inhibit --what=sleep:idle:handle-lid-switch --who=lineage-build --why='LineageOS build $NAME' sudo -n docker wait $NAME >/dev/null 2>&1 </dev/null &"
	$SSH "$HOST" "systemd-inhibit --list --no-legend | grep lineage-build" || echo "WARNING: no sleep inhibitor"
fi
echo "follow: ssh $HOST tail -f $BASE/logs/$NAME.log"
