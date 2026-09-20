#!/bin/sh
# app.sh reads stdin from $STDIN_PIPE, not the container's own stdin.
# Write to it: docker exec <container> sh -c 'echo "hello" > /run/stdin.pipe'
# Why not native stdin?: see README.md#problem.
set -eu

rm -f "$STDIN_PIPE" # /run persists across stop/start, drop any stale FIFO
(umask 0077 && mkfifo "$STDIN_PIPE")
chown "$APP_USER":"$APP_GROUP" "$STDIN_PIPE"

cd /home/"$APP_USER"

# Never open $STDIN_PIPE here: tini below would inherit the fd and
# hold it open for the container's whole life, blocking a real EOF.
exec tini -g -- gosu "$APP_USER" /usr/local/bin/leader.sh "$@"
