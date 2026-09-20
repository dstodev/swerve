#!/bin/sh
# run.sh - build and demonstrate the app image
set -eu

IMAGE_NAME=${IMAGE_TAG:-swerve-app-demo}
CONTAINER_NAME=$IMAGE_NAME
APP_USER=${APP_USER:-user}

this_dir="$(dirname -- "$(readlink --canonicalize -- "$0")")"
stdin_pipe=''

main() {
	trap cleanup EXIT

	build_image
	run_container

	app_exec ps -o pid,ppid,pgid,user,args
	app_exec ls -la /run
	app_exec pwd

	wait_for_log_lines "args (2): 'demo' 'forwarded arg'" 1

	set -- 'hello' 'world' 'goodbye'
	write_stdin "$@"
	wait_for_log_lines 'got: ' "$#"

	set -- HUP USR1 USR2
	send_signals "$@"
	wait_for_log_lines 'signal: ' "$#"

	set -- TERM
	send_signals "$@"
	wait_for_log_lines 'app: stdin closed, exiting' 1

	docker logs "$CONTAINER_NAME"
}

build_image() {
	docker build --build-arg USER_NAME="$APP_USER" \
		--tag "$IMAGE_NAME" "$this_dir/docker"
}

run_container() {
	# Self-heal from a stale container left behind by a prior run
	# that didn't reach its own EXIT trap (e.g. killed outright).
	docker rm --force "$CONTAINER_NAME" >/dev/null 2>&1 || true
	docker run --detach --name "$CONTAINER_NAME" \
		--cap-drop=ALL \
		--cap-add=SETUID --cap-add=SETGID --cap-add=CHOWN \
		--cap-add=KILL \
		--security-opt=no-new-privileges \
		"$IMAGE_NAME" demo 'forwarded arg' >/dev/null
	stdin_pipe=$(docker exec "$CONTAINER_NAME" sh -c 'printf %s "$STDIN_PIPE"')
	wait_for_pipe
}

app_exec() {
	printf '$'
	for arg in "$@"; do
		printf ' %s' "$(shquote "$arg")"
	done
	printf '\n'
	docker exec --user "$APP_USER" "$CONTAINER_NAME" "$@"
}

shquote() {
	printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# Runs "$@" every 0.1s, up to 20 times, until it exits 0.
retry() {
	for _ in $(seq 1 20); do
		if "$@"; then
			return 0
		fi
		sleep 0.1
	done
	echo "run.sh: timed out waiting for: $*" >&2
	exit 1
}

wait_for_pipe() {
	retry app_exec test -p "$stdin_pipe"
}

write_stdin() {
	for line in "$@"; do
		# shellcheck disable=SC2016 # $1/$2 expand in the invoked sh -c, not here
		app_exec sh -c 'printf "%s\n" "$1" > "$2"' -- "$line" "$stdin_pipe"
	done
}

log_lines_reached() {
	pattern=$1
	expected_lines=$2
	got=$(docker logs "$CONTAINER_NAME" 2>&1 | grep -c "$pattern" || true)
	[ "$got" -ge "$expected_lines" ]
}

wait_for_log_lines() {
	retry log_lines_reached "$1" "$2"
}

send_signals() {
	for sig in "$@"; do
		docker kill --signal "$sig" "$CONTAINER_NAME" >/dev/null
	done
}

cleanup() {
	docker rm --force "$CONTAINER_NAME" >/dev/null 2>&1 || true
}

main "$@"
