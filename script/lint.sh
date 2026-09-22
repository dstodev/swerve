#!/bin/sh
# lint.sh - static checks needing no tools beyond POSIX sh
set -eu

this_dir="$(dirname -- "$(readlink --canonicalize -- "$0")")"
repo_root="$this_dir/.."

main() {
	cd "$repo_root"
	status=0
	check_shell_syntax || status=1
	check_wait_signal_matches_trap || status=1
	exit "$status"
}

check_shell_syntax() {
	status=0
	for script in docker/*.sh script/*.sh; do
		if ! sh -n "$script"; then
			echo "lint.sh: syntax error in $script" >&2
			status=1
		fi
	done
	return "$status"
}

# keep-open.c WAIT_SIGNAL must be trapped by app.sh (see CLAUDE.md).
check_wait_signal_matches_trap() {
	signal=$(sed --quiet \
		's/.*WAIT_SIGNAL = SIG\([A-Z0-9]*\);.*/\1/p' docker/keep-open.c)
	if [ -z "$signal" ]; then
		echo 'lint.sh: WAIT_SIGNAL not found in keep-open.c' >&2
		return 1
	fi
	if ! grep --quiet --extended-regexp "^trap '.*' $signal\$" \
		docker/app.sh; then
		echo "lint.sh: app.sh does not trap $signal (WAIT_SIGNAL)" >&2
		return 1
	fi
}

main "$@"
