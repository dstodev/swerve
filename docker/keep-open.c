/* Opens the FIFO (argv[1]) read+write, forks, and returns: the
 * child holds that fd until wait_signal, then closes it so a reader
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
#include <sys/types.h>
#include <unistd.h>

static const int WAIT_SIGNAL = SIGTERM;

int main(int argc, char** argv)
{
	if (argc != 2) {
		return 2;
	}

	/* O_RDWR, not O_WRONLY: write-only would block this call until a
	 * reader shows up, racing leader.sh's own open. O_RDWR never blocks. */
	const int fd = open(argv[1], O_RDWR);
	if (fd < 0) {
		return 1;
	}

	/* Block every signal before forking (default disposition is
	 * terminate): tini -g's group broadcast reaches both processes,
	 * and blocking after fork would leave a window where it could
	 * kill either one before the child reaches sigwait. */
	sigset_t blocked;
	sigfillset(&blocked);
	sigprocmask(SIG_BLOCK, &blocked, NULL);

	const pid_t child = fork();
	if (child < 0) {
		return 1;
	}
	if (child > 0) {
		return 0; /* parent: fd is open, child holds it, we're done */
	}

	/* sigwait dequeues WAIT_SIGNAL atomically: no missed-signal race
	 * between checking a flag and pausing. */
	sigset_t wait_signals;
	sigemptyset(&wait_signals);
	sigaddset(&wait_signals, WAIT_SIGNAL);
	int caught;
	sigwait(&wait_signals, &caught);

	close(fd);
	return 0;
}
