// Minimal IPA extractor (zlib only). Built into LiteBoard itself: `LiteBoard --unzip <file.ipa> <destdir>`
// (a separate helper binary can be dropped or made non-executable by re-signing installers).
// `unzip` is not guaranteed on a jailbroken iPad. Extracts only Payload/ entries,
// rejects absolute paths, "..", and symlinks, verifies CRC32, keeps unix modes.
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <zlib.h>

static uint16_t u16(const uint8_t *p) { return p[0] | (p[1] << 8); }
static uint32_t u32(const uint8_t *p) { return p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24); }

static int mkdirs(char *path, mode_t mode) { // mkdir -p
	for (char *p = path + 1; *p; p++) {
		if (*p != '/') continue;
		*p = 0;
		if (mkdir(path, 0755) != 0 && errno != EEXIST) { *p = '/'; return -1; }
		*p = '/';
	}
	if (mkdir(path, mode) != 0 && errno != EEXIST) return -1;
	return 0;
}

static int safe_name(const char *n, size_t len) {
	if (len == 0 || n[0] == '/' || len > 1000) return 0;
	if (strncmp(n, "Payload/", 8) != 0) return 0;
	for (size_t i = 0; i + 1 < len; i++) if (n[i] == '.' && n[i + 1] == '.') return 0;
	return 1;
}

int lbunzip_extract(const char *ipa, const char *dest) {
	FILE *f = fopen(ipa, "rb");
	if (!f) { perror("open"); return 1; }
	fseek(f, 0, SEEK_END);
	long size = ftell(f);
	fseek(f, 0, SEEK_SET);
	if (size < 22 || size > (128L << 20)) { fprintf(stderr, "bad size\n"); return 1; }
	uint8_t *z = malloc(size);
	if (!z || fread(z, 1, size, f) != (size_t)size) { fprintf(stderr, "read failed\n"); return 1; }
	fclose(f);

	long e = size - 22; // end of central directory
	while (e >= 0 && u32(z + e) != 0x06054b50) e--;
	if (e < 0) { fprintf(stderr, "not a zip\n"); return 1; }
	unsigned count = u16(z + e + 10);
	uint32_t cdOff = u32(z + e + 16);
	if (cdOff >= (uint32_t)size) { fprintf(stderr, "bad directory\n"); return 1; }

	size_t dlen = strlen(dest);
	long p = cdOff;
	int extracted = 0;
	for (unsigned i = 0; i < count; i++) {
		if (p + 46 > size || u32(z + p) != 0x02014b50) { fprintf(stderr, "bad entry\n"); return 1; }
		uint16_t method = u16(z + p + 10);
		uint32_t crc = u32(z + p + 16), csize = u32(z + p + 20), usize = u32(z + p + 24);
		uint16_t nlen = u16(z + p + 28), xlen = u16(z + p + 30), clen = u16(z + p + 32);
		uint32_t attr = u32(z + p + 38), lho = u32(z + p + 42);
		const char *name = (const char *)(z + p + 46);
		if (p + 46 + nlen > size) { fprintf(stderr, "bad entry\n"); return 1; }
		p += 46 + nlen + xlen + clen;

		if (!safe_name(name, nlen)) continue;
		mode_t unixmode = (attr >> 16) & 0177777;
		if ((unixmode & S_IFMT) == S_IFLNK) continue;

		char path[2048];
		if (dlen + 1 + nlen + 1 > sizeof path) { fprintf(stderr, "path too long\n"); return 1; }
		snprintf(path, sizeof path, "%s/%.*s", dest, (int)nlen, name);

		if (name[nlen - 1] == '/') { // directory
			path[strlen(path) - 1] = 0;
			if (mkdirs(path, 0755) != 0) { perror(path); return 1; }
			continue;
		}
		char dir[2048];
		strcpy(dir, path);
		char *slash = strrchr(dir, '/');
		if (slash) { *slash = 0; if (mkdirs(dir, 0755) != 0) { perror(dir); return 1; } }

		if (lho + 30 > (uint32_t)size || u32(z + lho) != 0x04034b50) { fprintf(stderr, "bad local header\n"); return 1; }
		uint32_t dstart = lho + 30 + u16(z + lho + 26) + u16(z + lho + 28);
		if ((uint64_t)dstart + csize > (uint64_t)size) { fprintf(stderr, "truncated\n"); return 1; }

		uint8_t *out = malloc(usize ? usize : 1);
		if (!out) { fprintf(stderr, "oom\n"); return 1; }
		if (method == 0) {
			if (csize != usize) { fprintf(stderr, "bad stored size\n"); return 1; }
			memcpy(out, z + dstart, usize);
		} else if (method == 8) {
			z_stream s;
			memset(&s, 0, sizeof s);
			if (inflateInit2(&s, -15) != Z_OK) return 1;
			s.next_in = z + dstart; s.avail_in = csize;
			s.next_out = out; s.avail_out = usize;
			int r = inflate(&s, Z_FINISH);
			inflateEnd(&s);
			if (r != Z_STREAM_END || s.total_out != usize) { fprintf(stderr, "inflate failed: %s\n", path); return 1; }
		} else {
			fprintf(stderr, "unsupported method %u\n", method);
			return 1;
		}
		if ((uint32_t)crc32(0, out, usize) != crc) { fprintf(stderr, "crc mismatch: %s\n", path); return 1; }

		mode_t mode = unixmode & 07777;
		if (!mode) mode = 0644;
		int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
		if (fd < 0) { perror(path); return 1; }
		size_t off = 0;
		while (off < usize) {
			ssize_t w = write(fd, out + off, usize - off);
			if (w <= 0) { perror("write"); return 1; }
			off += w;
		}
		fchmod(fd, mode);
		close(fd);
		free(out);
		extracted++;
	}
	free(z);
	if (!extracted) { fprintf(stderr, "no Payload entries\n"); return 1; }
	return 0;
}

#ifdef LBUNZIP_STANDALONE
int main(int argc, char **argv) {
	if (argc != 3) { fprintf(stderr, "usage: lbunzip file.ipa destdir\n"); return 2; }
	return lbunzip_extract(argv[1], argv[2]);
}
#endif
