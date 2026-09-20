#!/bin/sh

# Example application.
# Echoes input from stdin and responds to some signals.

echo "app started, pid $$"
printf 'args (%d):' "$#"
[ "$#" -eq 0 ] || printf " '%s'" "$@"
printf '\n'
printf 'pwd: %s\n' "$(pwd)"

interrupted=0

on_signal() {
	interrupted=1
	echo "$(date '+%H:%M:%S') signal: $1"
}

# Example signals, print on receipt
trap 'on_signal HUP' HUP
trap 'on_signal USR1' USR1
trap 'on_signal USR2' USR2

# Important to set TERM disposition away from default (terminate).
# keep-open.c closes the FIFO on TERM, letting this app read EOF and
# exit gracefully. Must match keep-open.c's hardcoded signal if changed.
trap 'on_signal TERM' TERM

while :; do
	if IFS= read -r line; then
		echo "$(date '+%H:%M:%S') got: $line"
	elif [ "$interrupted" -eq 1 ]; then
		# read was interrupted by a trapped signal, not EOF
		interrupted=0 # reset
	else
		break
	fi
done

# normal shutdown: TERM drops the FIFO's writer, so read() EOFs here
echo 'app: stdin closed, exiting'
