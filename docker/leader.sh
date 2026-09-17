#!/bin/sh
# tini forks a new process replaced by this script, leading its process group.
# tini -g delivers signals it receives to all processes in this group.
set -eu

keep-open "$STDIN_PIPE" & # closes $STDIN_PIPE on SIGTERM
keep_open_pid=$!

# A failed background job never trips set -e, so without this check
# a missing/broken keep-open would leave nothing to open the FIFO's
# write side, and the blocking open below would hang forever with no
# explanation in the logs.
sleep 0.1
if ! kill -0 "$keep_open_pid" 2>/dev/null; then
	echo 'leader.sh: keep-open failed to start' >&2
	exit 1
fi

# Replace fd 0 with the FIFO as `O_RDONLY`; with -i it'd be the containerd-shim
# stream docker exposes (the stream affected by OpenStdin/StdinOnce).
exec 0<"$STDIN_PIPE"
exec /home/"$APP_USER"/app.sh
