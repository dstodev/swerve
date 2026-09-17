/* Opens the FIFO given as argv[1] read+write and holds it open
 * until SIGTERM, then closes it so a separate reader on the same
 * FIFO can finally EOF. Must open it itself rather than inherit an
 * fd from entrypoint.sh: tini (PID 1) is entrypoint.sh's own exec
 * target, so any fd entrypoint.sh opened survives, inherited, for
 * tini's entire lifetime (the container's lifetime), permanently
 * counting as a writer no matter what closes its own copy. See
 * leader.sh for where this gets started.
 *
 * Also a C binary rather than a shell script because busybox ash's
 * signal handling proved unreliable here: a trap closing an fd
 * after interrupting a blocking `wait` did not reliably surface as
 * EOF to a reader elsewhere, even though the close itself took
 * effect. */
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	if (argc != 2)
		return 2;

	/* O_RDWR, not O_WRONLY: write-only would block this call until a
	 * reader shows up, racing leader.sh's own open. O_RDWR never blocks. */
	const int fd = open(argv[1], O_RDWR);
	if (fd < 0)
		return 1;

	/* Block every signal so none can use its default disposition
	 * (terminate) before we're ready: tini -g's group broadcast
	 * reaches this process too, and it must outlive whatever the app
	 * it's paired with does with signals it doesn't otherwise care
	 * about. sigwait then synchronously dequeues SIGTERM specifically,
	 * with no missed-signal race between checking a flag and pausing. */
	sigset_t blocked;
	sigfillset(&blocked);
	sigprocmask(SIG_BLOCK, &blocked, NULL);

	sigset_t wait_for_term;
	sigemptyset(&wait_for_term);
	sigaddset(&wait_for_term, SIGTERM);
	int caught;
	sigwait(&wait_for_term, &caught);

	close(fd);
	return 0;
}
