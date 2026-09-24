/* Opens the FIFO (argv[1]) read+write, forks, and returns: the
 * child holds that fd until CLOSE_SIGNAL, then closes it so a reader
 * elsewhere finally sees EOF. Run in the foreground by leader.sh (no
 * shell `&`), so nothing races its startup: the fd is already open
 * and the child already forked by the time this returns.
 *
 * Opens fresh rather than inheriting an fd from entrypoint.sh:
 * whatever entrypoint.sh opened would be inherited by tini and held
 * open for the container's whole life, blocking EOF regardless of
 * what closes downstream.
 *
 * A C binary, not a shell script: a shell trap closing an fd after
 * interrupting a blocking `wait` didn't reliably surface as EOF to
 * a reader elsewhere in testing. sigwait has no such race. */
#include <fcntl.h>
#include <signal.h>
#include <unistd.h> /* NOLINT(misc-include-cleaner): false positive */

#ifndef CLOSE_SIGNAL
#error "Define CLOSE_SIGNAL, e.g. -DCLOSE_SIGNAL=SIGTERM (see app.Dockerfile)"
#endif

int main(int argc, char** argv)
{
	if (argc != 2) {
		return 2;
	}

	/* O_RDWR, not O_WRONLY: write-only would block this call until a
	 * reader shows up, racing leader.sh's own open. O_RDWR never blocks. */
	const int fifo_fd = open(argv[1], O_RDWR | O_CLOEXEC);
	if (fifo_fd < 0) {
		return 1;
	}

	/* Block every signal before forking (default disposition is
	 * terminate): tini -g's group broadcast reaches both processes,
	 * and blocking after fork would leave a window where it could
	 * kill either one before the child reaches sigwait. A blocked
	 * signal isn't lost, it stays pending until sigwait collects it. */
	sigset_t blocked;
	sigfillset(&blocked);
	pthread_sigmask(SIG_BLOCK, &blocked, NULL);

	const pid_t child = fork();
	if (child < 0) {
		return 1;
	}
	if (child > 0) {
		return 0; /* parent: fd is open, child holds it, we're done */
	}

	/* sigwait returns at once if CLOSE_SIGNAL is already pending (it
	 * arrived after the block above, before this call), else sleeps
	 * until it arrives. Either way it dequeues it: never missed. */
	sigset_t wait_signals;
	sigemptyset(&wait_signals);
	sigaddset(&wait_signals, CLOSE_SIGNAL);
	int caught = 0;
	sigwait(&wait_signals, &caught);

	close(fifo_fd);
	return 0;
}
