#import "LBRun.h"
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>
#import <string.h>
#import <errno.h>

extern char **environ;

static const int kNoRoot = -1;
static const int kHelperNotRoot = 3; // lbroot exit code when setuid didn't take effect
static NSMutableString *sLog;

static void logf_(NSString *s) {
	if (!sLog) sLog = [NSMutableString string];
	[sLog appendFormat:@"%@\n", s];
}

NSString *LBRootLog(void) { return sLog ?: @""; }

// Spawns argv[0], optionally feeding `input` on stdin; stdout/stderr go to the log.
// Returns the exit status or kNoRoot.
static int spawnWait(const char *label, char *const argv[], const char *input) {
	if (access(argv[0], X_OK) != 0) {
		logf_([NSString stringWithFormat:@"%s: cannot execute %s (%s)", label, argv[0], strerror(errno)]);
		return kNoRoot;
	}
	int in[2], out[2];
	if (pipe(in) != 0 || pipe(out) != 0) return kNoRoot;
	posix_spawn_file_actions_t fa;
	posix_spawn_file_actions_init(&fa);
	posix_spawn_file_actions_adddup2(&fa, in[0], 0);
	posix_spawn_file_actions_adddup2(&fa, out[1], 1);
	posix_spawn_file_actions_adddup2(&fa, out[1], 2);
	posix_spawn_file_actions_addclose(&fa, in[1]);
	posix_spawn_file_actions_addclose(&fa, out[0]);
	pid_t pid;
	int err = posix_spawn(&pid, argv[0], &fa, NULL, argv, environ);
	posix_spawn_file_actions_destroy(&fa);
	close(in[0]); close(out[1]);
	if (err != 0) {
		close(in[1]); close(out[0]);
		logf_([NSString stringWithFormat:@"%s: spawn failed: %s", label, strerror(err)]);
		return kNoRoot;
	}
	if (input) write(in[1], input, strlen(input));
	close(in[1]);
	char buf[512]; ssize_t n; NSMutableData *data = [NSMutableData data];
	while ((n = read(out[0], buf, sizeof buf)) > 0 && data.length < 2048) [data appendBytes:buf length:n];
	close(out[0]);
	int st = 0;
	waitpid(pid, &st, 0);
	int rc = WIFEXITED(st) ? WEXITSTATUS(st) : kNoRoot;
	NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	logf_([NSString stringWithFormat:@"%s: exit %d%@%@", label, rc, text.length ? @": " : @"", text]);
	return rc;
}

int LBRunRoot(NSString *appPath, NSString *scriptRel, NSString *arg) {
	sLog = [NSMutableString string];
	NSString *helper = [appPath stringByAppendingPathComponent:@"lbroot"];
	NSString *script = [appPath stringByAppendingPathComponent:scriptRel];
	const char *carg = arg.UTF8String;

	// 1. setuid helper (works when the installer preserved root ownership + setuid)
	char *a1[] = { (char *)helper.fileSystemRepresentation, (char *)carg, NULL };
	int rc = spawnWait("lbroot", a1, NULL);
	if (rc != kNoRoot && rc != kHelperNotRoot) return rc;

	// 2. su with the default root password; su reads it from stdin when there is no tty.
	// Its location differs between jailbreaks, so try the usual places, then let sh search PATH.
	NSString *cmd = [NSString stringWithFormat:@"/bin/sh '%@' %@", script, arg];
	const char *suPaths[] = { "/usr/bin/su", "/bin/su", "/usr/local/bin/su", "/usr/sbin/su", "/sbin/su", "/var/jb/usr/bin/su", NULL };
	for (int i = 0; suPaths[i]; i++) {
		if (access(suPaths[i], X_OK) != 0) continue;
		char *a2[] = { (char *)suPaths[i], "root", "-c", (char *)cmd.UTF8String, NULL };
		return spawnWait("su", a2, "alpine\n");
	}
	logf_(@"su not found at the usual paths, asking sh to search PATH");
	NSString *viaSh = [NSString stringWithFormat:@"su root -c \"%@\"", cmd];
	char *a3[] = { "/bin/sh", "-c", (char *)viaSh.UTF8String, NULL };
	return spawnWait("sh+su", a3, "alpine\n");
}
