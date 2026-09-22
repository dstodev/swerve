# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

Template: durable, scriptable stdin for a container via a FIFO, plus root to
unprivileged user handoff. See README.md for rationale and diagrams.

## Commands

- `make help`: list goals
- `make image`: build image (`docker build` of `docker/`)
- `make lint`: `lint.sh` static checks (`sh -n`, `WAIT_SIGNAL` matches the
  `app.sh` trap)
- `make test`: build, run, assert invariants, tee output to `test.log`, exit
  with `test.sh` status
- `make shell`: shell in the built image
- `IMAGE_TAG`, `APP_USER`, `TEST_LOG` override via make vars or env

No unit tests. `test.sh` is the only test: it runs one container and asserts
invariants via `check` (PASS/FAIL tally, non-zero exit on any FAIL), polling
`docker logs` for expected lines. Run it after any change under `docker/`.
Add a `test_` function plus a `check` for each new invariant. Extra scenarios
(failing app exit code, each capability required, `keep-open` TERM race) start
their own containers named `$CONTAINER_NAME-*`.

No formatter or third-party linter wired up. `.clang-format` exists (80 cols,
tab indent) for `keep-open.c`. CI (`.github/workflows/ci.yml`) runs `make lint
test`. `keep-open.c` builds with `-Wall -Wextra -Werror`. Shell scripts are
POSIX `sh` (not bash), except the `test` Make goal, which sets `SHELL := bash`
for `PIPESTATUS`.

## Architecture

Process chain inside the container:

`entrypoint.sh` (root) creates FIFO at `$STDIN_PIPE` and `chown`s it, then `exec
tini -g -- gosu $APP_USER leader.sh` which runs `keep-open`, redirects fd 0 from
the FIFO, then `exec app.sh`.

Invariants that span files:

- `entrypoint.sh` must never open the FIFO. tini would inherit the fd and hold a
  writer open for the container's life, so the app could never see EOF.
- `keep-open` (C, static) opens the FIFO `O_RDWR`, forks, parent returns, child
  holds the fd until `SIGTERM`, then closes it. That close is what gives
  `app.sh` a real EOF on shutdown.
- `keep-open` must block signals before `fork()`. Blocked signals stay pending,
  and `sigwait` collects them, so none is missed. Do not move the block after
  the fork.
- `WAIT_SIGNAL` (`SIGTERM`) in `keep-open.c` must match the trap in `app.sh`.
  `app.sh` must trap `TERM` so the default action (terminate) does not kill it
  before EOF.
- `tini -g` rebroadcasts signals to the whole process group, so `keep-open` and
  `app.sh` both receive them.
- `leader.sh` calls `keep-open` in the foreground (no `&`), so the FIFO writer
  exists before `exec 0<"$STDIN_PIPE"`.
- `docker/app.sh` is the placeholder to replace. Everything else is
  app-agnostic.

Image layout: scripts and `keep-open` live in `/usr/local/bin`. `entrypoint.sh`
is `0500` (root only) so the app user cannot read or run it. Cross-script execs
use absolute `/usr/local/bin/...` paths, not `PATH` lookup. `test.sh` runs the
container with `--cap-drop=ALL` plus `SETUID SETGID CHOWN KILL` and
`no-new-privileges`, so new root-side steps in `entrypoint.sh` may need another
capability.
