// Setuid-root trampoline: runs <dir of this binary>/SCRIPT_REL with the single argument
// given. The script validates the argument. Built once per app with
// -DSCRIPT_REL="ctl/<script>.sh". The app can live anywhere (/Applications or an
// installd container), so the path is derived from the executable's own location.
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef SCRIPT_REL
#error "define SCRIPT_REL"
#endif

int main(int argc, char **argv) {
	if (argc != 2) return 2;
	if (setuid(0) != 0 || geteuid() != 0) {
		fprintf(stderr, "lbroot: not setuid root\n");
		return 3;
	}
	setgid(0);

	char raw[PATH_MAX], self[PATH_MAX], script[PATH_MAX + 32];
	uint32_t n = sizeof raw;
	if (_NSGetExecutablePath(raw, &n) != 0 || !realpath(raw, self)) return 5;
	char *slash = strrchr(self, '/');
	if (!slash) return 5;
	*slash = 0;
	snprintf(script, sizeof script, "%s/%s", self, SCRIPT_REL);

	char *args[] = { "/bin/sh", script, argv[1], NULL };
	char *env[] = { "PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin", NULL };
	execve("/bin/sh", args, env);
	return 4;
}
