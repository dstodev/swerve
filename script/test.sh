#!/bin/sh
# test.sh - build the image, run it, assert the documented invariants
set -eu

IMAGE_NAME=${IMAGE_TAG:-swerve-test}
CONTAINER_NAME=$IMAGE_NAME
APP_USER=${APP_USER:-user}
REQUIRED_CAPS='SETUID SETGID CHOWN KILL'
KEEP_OPEN=/usr/local/bin/keep-open

this_dir="$(dirname -- "$(readlink --canonicalize -- "$0")")"
repo_root="$this_dir/.."
stdin_pipe=''
passed=0
failed=0

main() {
	trap cleanup EXIT

	build_image
	run_container "$CONTAINER_NAME" "$REQUIRED_CAPS"
	stdin_pipe=$(root_exec sh -c 'printf %s "$STDIN_PIPE"')
	wait_for_pipe

	check 'app receives forwarded args' test_app_receives_forwarded_args
	check 'app starts in its user home' test_app_starts_in_user_home
	check 'app runs as the unprivileged user' test_app_runs_as_app_user
	check 'entrypoint.sh is unreadable and unrunnable by app user' \
		test_entrypoint_hidden_from_app_user
	check 'FIFO is owned by app user with mode 600' test_fifo_owner_and_mode
	check 'tini is pid 1' test_tini_is_pid_1
	check 'keep-open is statically linked' test_keep_open_is_static
	check 'app holds the FIFO as stdin' test_app_holds_fifo
	check 'keep-open holds the FIFO' test_keep_open_holds_fifo
	check 'tini does not hold the FIFO' test_tini_does_not_hold_fifo

	set -- 'hello' 'world' 'goodbye'
	write_stdin "$@"
	check 'stdin lines reach the app' test_stdin_lines_reach_app "$@"

	set -- HUP USR1 USR2
	send_signals "$@"
	check 'signals reach the app' test_signals_reach_app "$@"

	set -- TERM
	send_signals "$@"
	check 'TERM gives the app EOF on stdin' test_term_gives_app_eof
	check 'container exits 0 after graceful shutdown' \
		test_container_exits_zero

	check 'app exit code propagates to the container' \
		test_app_exit_code_propagates
	for cap in $REQUIRED_CAPS; do
		check "capability $cap is required" test_cap_is_required "$cap"
	done
	check 'keep-open never misses TERM' test_keep_open_never_misses_term

	summarize
}

build_image() {
	docker build --build-arg USER_NAME="$APP_USER" \
		--tag "$IMAGE_NAME" "$repo_root/docker"
}

# Starts container $1 with capabilities $2 (space-separated) and any
# further "$@" docker run options.
run_container() {
	name=$1
	caps=$2
	shift 2
	for cap in $caps; do
		set -- "$@" "--cap-add=$cap"
	done
	# Self-heal from a stale container left behind by a prior run
	# that didn't reach its own EXIT trap (e.g. killed outright).
	docker rm --force "$name" >/dev/null 2>&1 || true
	docker run --detach --name "$name" \
		--cap-drop=ALL \
		--security-opt=no-new-privileges \
		"$@" \
		"$IMAGE_NAME" 'arg 1' 'arg 2' >/dev/null
}

# Runs "$@" and tallies the result under the given description.
check() {
	description=$1
	shift
	if "$@"; then
		passed=$((passed + 1))
		printf 'PASS: %s\n' "$description"
	else
		failed=$((failed + 1))
		printf 'FAIL: %s\n' "$description"
	fi
}

summarize() {
	printf '\n%d passed, %d failed\n' "$passed" "$failed"
	if [ "$failed" -gt 0 ]; then
		printf '\n--- container logs ---\n'
		docker logs "$CONTAINER_NAME" 2>&1
		exit 1
	fi
}

app_exec() {
	docker exec --user "$APP_USER" "$CONTAINER_NAME" "$@"
}

root_exec() {
	docker exec "$CONTAINER_NAME" "$@"
}

# Runs "$@" every 0.1s, up to 20 times, until it exits 0.
retry() {
	for _ in $(seq 1 20); do
		if "$@"; then
			return 0
		fi
		sleep 0.1
	done
	echo "test.sh: timed out waiting for: $*" >&2
	return 1
}

wait_for_pipe() {
	retry app_exec test -p "$stdin_pipe"
}

test_app_receives_forwarded_args() {
	wait_for_log_lines "args (2): 'arg 1' 'arg 2'" 1
}

test_app_starts_in_user_home() {
	wait_for_log_lines "pwd: /home/$APP_USER" 1
}

test_app_runs_as_app_user() {
	pid=$(app_pid)
	[ -n "$pid" ] || return 1
	owner=$(root_exec stat -c %U "/proc/$pid") || return 1
	[ "$owner" = "$APP_USER" ]
}

test_entrypoint_hidden_from_app_user() {
	entrypoint=/usr/local/bin/entrypoint.sh
	! app_exec test -r "$entrypoint" && ! app_exec test -x "$entrypoint"
}

test_fifo_owner_and_mode() {
	actual=$(app_exec stat -c '%U %a' "$stdin_pipe") || return 1
	[ "$actual" = "$APP_USER 600" ]
}

test_tini_is_pid_1() {
	[ "$(root_exec cat /proc/1/comm)" = 'tini' ]
}

# Static binaries list no "=>" library lines. busybox is the dynamic
# control that proves the detection works.
test_keep_open_is_static() {
	root_exec test -x "$KEEP_OPEN" &&
		root_exec ldd /bin/busybox | grep --quiet '=>' &&
		! root_exec ldd "$KEEP_OPEN" | grep --quiet '=>'
}

test_app_holds_fifo() {
	pid=$(app_pid)
	[ -n "$pid" ] && holds_fifo "$APP_USER" "$pid"
}

test_keep_open_holds_fifo() {
	pid=$(app_exec pgrep keep-open | head --lines 1)
	[ -n "$pid" ] && holds_fifo "$APP_USER" "$pid"
}

test_tini_does_not_hold_fifo() {
	status=0
	holds_fifo root 1 || status=$?
	[ "$status" -eq 1 ]
}

write_stdin() {
	for line in "$@"; do
		# shellcheck disable=SC2016 # $1/$2 expand in the invoked sh -c, not here
		app_exec sh -c 'printf "%s\n" "$1" > "$2"' -- "$line" "$stdin_pipe"
	done
}

test_stdin_lines_reach_app() {
	for line in "$@"; do
		wait_for_log_lines "got: $line" 1 || return 1
	done
}

send_signals() {
	for sig in "$@"; do
		docker kill --signal "$sig" "$CONTAINER_NAME" >/dev/null
	done
}

test_signals_reach_app() {
	for sig in "$@"; do
		wait_for_log_lines "signal: $sig" 1 || return 1
	done
}

test_term_gives_app_eof() {
	wait_for_log_lines 'app: stdin closed, exiting' 1
}

test_container_exits_zero() {
	code=$(container_exit_code "$CONTAINER_NAME") || code=''
	[ "$code" -eq 0 ]
}

# Swaps in an app that exits nonzero, so tini's exit status is the app's.
test_app_exit_code_propagates() {
	expected=7
	name=$CONTAINER_NAME-failing-app
	dir=$(mktemp --directory)
	printf '#!/bin/sh\nexit %d\n' "$expected" >"$dir/app.sh"
	chmod 0555 "$dir/app.sh"
	run_container "$name" "$REQUIRED_CAPS" \
		--volume "$dir/app.sh:/usr/local/bin/app.sh:ro"
	code=$(container_exit_code "$name") || code=''
	docker rm --force "$name" >/dev/null 2>&1 || true
	rm --recursive --force "$dir"
	[ "$code" = "$expected" ]
}

# Every capability in REQUIRED_CAPS must be load-bearing: dropping any
# one breaks the container lifecycle.
test_cap_is_required() {
	remaining=$(printf '%s\n' $REQUIRED_CAPS |
		grep --line-regexp --invert-match "$1" | tr '\n' ' ')
	! lifecycle_completes "$CONTAINER_NAME-without-$1" "$remaining" 2>/dev/null
}

# Sends TERM as soon as keep-open returns, before its child can reach
# sigwait. A missed TERM leaves the reader blocked until timeout.
test_keep_open_never_misses_term() {
	docker run --rm --name "$CONTAINER_NAME-term-race" \
		--entrypoint sh "$IMAGE_NAME" -c '
		cd /tmp
		for _ in $(seq 1 100); do
			rm -f pipe && mkfifo pipe || exit 1
			keep-open pipe || exit 1
			exec 3<pipe
			pkill -TERM keep-open
			timeout 2 cat <&3 || exit 1
			exec 3<&-
		done
	'
}

# Whether container $1 starts, gets TERM, and exits 0 through app EOF.
lifecycle_completes() {
	status=0
	(
		CONTAINER_NAME=$1
		run_container "$CONTAINER_NAME" "$2"
		wait_for_log_lines 'app started' 1 &&
			send_signals TERM &&
			wait_for_log_lines 'app: stdin closed, exiting' 1 &&
			[ "$(container_exit_code "$CONTAINER_NAME")" -eq 0 ]
	) || status=$?
	docker rm --force "$1" >/dev/null 2>&1 || true
	return "$status"
}

# Prints the exit code of container $1 once it stops.
container_exit_code() {
	timeout 10 docker wait "$1"
}

log_lines_reached() {
	pattern=$1
	expected_lines=$2
	got=$(docker logs "$CONTAINER_NAME" 2>&1 |
		grep --count --fixed-strings -- "$pattern" || true)
	[ "$got" -ge "$expected_lines" ]
}

wait_for_log_lines() {
	retry log_lines_reached "$1" "$2"
}

# Pid of the app.sh shell, parsed from the app's startup line.
app_pid() {
	docker logs "$CONTAINER_NAME" 2>&1 |
		sed --quiet 's/^app started, pid //p' | head --lines 1
}

# Whether process $2, run as user $1, has the FIFO open: 0 yes, 1 no,
# 2 fds unreadable. Runs as the target's own user because the container
# lacks CAP_SYS_PTRACE.
holds_fifo() {
	docker exec --user "$1" "$CONTAINER_NAME" sh -c '
		seen=0
		for fd in /proc/"$1"/fd/*; do
			target=$(readlink "$fd") || continue
			seen=1
			[ "$target" = "$2" ] && exit 0
		done
		[ "$seen" -eq 1 ] || exit 2
		exit 1
	' -- "$2" "$stdin_pipe"
}

cleanup() {
	docker ps --all --quiet --filter "name=^$CONTAINER_NAME" |
		xargs --no-run-if-empty docker rm --force >/dev/null 2>&1 || true
}

main "$@"
