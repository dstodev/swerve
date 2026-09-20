#!/bin/sh
# tini forks a new process replaced by this script, leading its process group.
# tini -g delivers signals it receives to all processes in this group.
set -eu

# No `&`: see keep-open.c, it forks its own background half and only
# returns once ready.
if ! keep-open "$STDIN_PIPE"; then
	echo 'leader.sh: keep-open failed to start' >&2
	exit 1
fi

# Replace fd 0 with the FIFO as `O_RDONLY`. With -i it'd replace the
# containerd-shim stream (the one affected by OpenStdin/StdinOnce).
exec 0<"$STDIN_PIPE"
exec /usr/local/bin/app.sh "$@"
