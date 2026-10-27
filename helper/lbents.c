// Prints the entitlements embedded in a Mach-O's code signature, without needing `ldid` or
// `codesign` on the device. Handles fat and thin 32/64-bit files.
//   LiteBoard --entitlements <binary>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint32_t be32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]; }
static uint32_t le32(const uint8_t *p) { return p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24); }

static int dump_slice(const uint8_t *f, size_t fsize, size_t off, const char *label) {
	if (off + 32 > fsize) return 0;
	const uint8_t *m = f + off;
	uint32_t magic = le32(m);
	size_t hdr;
	if (magic == 0xfeedface) hdr = 28;
	else if (magic == 0xfeedfacf) hdr = 32;
	else { printf("(%s: not a Mach-O)\n", label); return 0; }
	uint32_t ncmds = le32(m + 16);
	size_t p = off + hdr;
	for (uint32_t i = 0; i < ncmds && p + 8 <= fsize; i++) {
		uint32_t cmd = le32(f + p), size = le32(f + p + 4);
		if (size < 8 || p + size > fsize) break;
		if (cmd == 0x1d && size >= 16) { // LC_CODE_SIGNATURE
			size_t sig = off + le32(f + p + 8);
			uint32_t sigsize = le32(f + p + 12);
			if (sig + 12 > fsize || sig + sigsize > fsize) { printf("(%s: bad signature range)\n", label); return 0; }
			if (be32(f + sig) != 0xfade0cc0) { printf("(%s: no signature superblob)\n", label); return 0; }
			uint32_t count = be32(f + sig + 8);
			for (uint32_t b = 0; b < count && sig + 12 + (size_t)b * 8 + 8 <= fsize; b++) {
				uint32_t boff = be32(f + sig + 12 + b * 8 + 4);
				size_t blob = sig + boff;
				if (blob + 8 > fsize) continue;
				if (be32(f + blob) == 0xfade7171) { // embedded entitlements (XML plist)
					uint32_t len = be32(f + blob + 4);
					if (len < 8 || blob + len > fsize) continue;
					printf("--- %s\n", label);
					fwrite(f + blob + 8, 1, len - 8, stdout);
					printf("\n");
					return 1;
				}
			}
			printf("(%s: signed, but no embedded entitlements)\n", label);
			return 0;
		}
		p += size;
	}
	printf("(%s: no code signature)\n", label);
	return 0;
}

int lbents_dump(const char *path) {
	FILE *fp = fopen(path, "rb");
	if (!fp) { perror(path); return 1; }
	fseek(fp, 0, SEEK_END);
	long n = ftell(fp);
	fseek(fp, 0, SEEK_SET);
	if (n < 32 || n > (200L << 20)) { fprintf(stderr, "bad size\n"); return 1; }
	uint8_t *f = malloc(n);
	if (!f || fread(f, 1, n, fp) != (size_t)n) { fprintf(stderr, "read failed\n"); return 1; }
	fclose(fp);

	int found = 0;
	if (be32(f) == 0xcafebabe) { // fat, big-endian
		uint32_t cnt = be32(f + 4);
		for (uint32_t i = 0; i < cnt && 8 + (size_t)i * 20 + 20 <= (size_t)n; i++) {
			const uint8_t *a = f + 8 + i * 20;
			char label[64];
			snprintf(label, sizeof label, "%s (cputype 0x%x subtype 0x%x)", path, be32(a), be32(a + 4));
			found += dump_slice(f, n, be32(a + 8), label);
		}
	} else {
		found += dump_slice(f, n, 0, path);
	}
	free(f);
	return found ? 0 : 1;
}

#ifdef LBENTS_STANDALONE
int main(int argc, char **argv) {
	if (argc != 2) { fprintf(stderr, "usage: lbents <binary>\n"); return 2; }
	return lbents_dump(argv[1]);
}
#endif
