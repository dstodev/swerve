#!/bin/sh

# Example application.
# Echoes input from stdin and responds to some signals.

echo "app started, pid $$"

interrupted=0

on_signal() {
	interrupted=1
	echo "$(date '+%H:%M:%S') signal: $1"
}

trap 'on_signal HUP' HUP
trap 'on_signal USR1' USR1
trap 'on_signal USR2' USR2
trap 'on_signal TERM' TERM

while :; do
	if IFS= read -r line; then
		echo "$(date '+%H:%M:%S') got: $line"
	elif [ "$interrupted" -eq 1 ]; then
		interrupted=0 # read was interrupted by a trapped signal, not EOF
	else
		break
	fi
done

# normal shutdown: TERM drops the FIFO's writer, so read() EOFs here
echo 'app: stdin closed, exiting'
