#!/bin/sh
# app.sh reads input from this FIFO, not the container's own stdin.
# Feed it via `docker exec <container> sh -c '... > /run/stdin.pipe'`.
#
# Not native stdin, because:
# - `-i` is a caller-supplied flag. Without it, PID 1's fd 0 EOFs at
#   startup and a stdin-reading app exits immediately. `docker run
#   -id` (OpenStdin=true, StdinOnce=false) plus writes to
#   /proc/1/fd/0 is a fair alternative when `-i` is guaranteed. A
#   FIFO works the same way regardless of how the container is run.
# - `docker attach` isn't reliably scriptable for one-shot writes:
#   closing its input stream doesn't make it return.
set -eu

rm -f "$STDIN_PIPE" # /run persists across stop/start, drop any stale FIFO
(umask 0077 && mkfifo "$STDIN_PIPE")
chown "$APP_USER":"$APP_GROUP" "$STDIN_PIPE"

echo

# Never open $STDIN_PIPE in this script: tini below would inherit and
# hold it open forever. leader.sh and keep-open open it fresh instead.
exec tini -g -- gosu "$APP_USER" /home/"$APP_USER"/leader.sh
