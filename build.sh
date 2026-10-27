#!/bin/sh
# Builds out/installer.ipa (LiteBoard), out/LiteSuite.ipa (LiteBoard + LiteKB) and out/LiteboardRemove.ipa (needs Theos in ~/theos, ldid, python3).
set -e
cd "$(dirname "$0")"
export THEOS=${THEOS:-$HOME/theos}
export PATH="/opt/homebrew/opt/make/libexec/gnubin:$PATH"
SDK=$THEOS/sdks/iPhoneOS10.3.sdk
ROOT=$PWD
OUT=$ROOT/out
rm -rf "$OUT" && mkdir -p "$OUT"

helper() { # helper <script path relative to the app bundle> <output>
	clang -target armv7-apple-ios8.0 -isysroot "$SDK" -Os -DSCRIPT_REL="\"$1\"" \
		-Wl,-w -o "$2" helper/lbroot.c
	ldid -S"$ROOT/entitlements.plist" "$2"
}

# --- lbunzip (used by the in-app updater, runs as root)
clang -target armv7-apple-ios8.0 -isysroot "$SDK" -Os -Wl,-w -lz -o "$OUT/lbunzip" helper/lbunzip.c
ldid -S"$ROOT/entitlements.plist" "$OUT/lbunzip"

# --- LiteBoard (installer.ipa)
make clean >/dev/null 2>&1 || true
make
APP=$ROOT/.theos/obj/debug/LiteBoard.app
STAGE=$OUT/stage-installer && mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/LiteBoard.app"
B=$STAGE/Payload/LiteBoard.app
mkdir -p "$B/ctl" && cp -R layout/usr layout/Library "$B/ctl/" && cp ctl/setup.sh "$B/ctl/"
helper ctl/setup.sh "$B/lbroot"
cp "$OUT/lbunzip" "$B/lbunzip"

# --- LiteKB keyboard extension (goes into LiteSuite.ipa, inside LiteBoard.app/PlugIns)
KBX=$OUT/LiteKB.appex && mkdir -p "$KBX"
clang -target armv7-apple-ios9.0 -isysroot "$SDK" -fobjc-arc -Os -fapplication-extension \
	-undefined dynamic_lookup -framework UIKit -framework Foundation \
	-Wl,-e,_NSExtensionMain -Wl,-w -o "$KBX/LiteKB" LiteKB/KeyboardViewController.m
cp LiteKB/Info.plist "$KBX/Info.plist"
ldid -S"$ROOT/LiteKB/entitlements.plist" "$KBX/LiteKB"
SSTAGE=$OUT/stage-suite && mkdir -p "$SSTAGE" && cp -R "$STAGE/Payload" "$SSTAGE/Payload"
mkdir -p "$SSTAGE/Payload/LiteBoard.app/PlugIns" && cp -R "$KBX" "$SSTAGE/Payload/LiteBoard.app/PlugIns/LiteKB.appex"

# --- LiteboardRemove (LiteboardRemove.ipa)
(cd Remove && make clean >/dev/null 2>&1 || true; make)
RSTAGE=$OUT/stage-remove && mkdir -p "$RSTAGE/Payload"
cp -R Remove/.theos/obj/debug/LiteboardRemove.app "$RSTAGE/Payload/LiteboardRemove.app"
RB=$RSTAGE/Payload/LiteboardRemove.app
mkdir -p "$RB/ctl" && cp Remove/ctl/remove.sh "$RB/ctl/"
helper ctl/remove.sh "$RB/lbroot"

# --- zip with explicit modes (setuid on lbroot; Python's zipfile keeps them)
python3 -I - "$OUT" <<'EOF'
import os, sys, zipfile
out = sys.argv[1]
def pack(stage, ipa):
    with zipfile.ZipFile(os.path.join(out, ipa), "w", zipfile.ZIP_DEFLATED) as z:
        for d, _, files in os.walk(stage):
            for f in sorted(files):
                p = os.path.join(d, f)
                rel = os.path.relpath(p, stage)
                info = zipfile.ZipInfo(rel, (2026, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                if f == "lbroot":
                    mode = 0o106755          # setuid; owner must be root to take effect
                elif os.access(p, os.X_OK):
                    mode = 0o100755
                else:
                    mode = 0o100644
                info.external_attr = mode << 16
                info.create_system = 3
                z.writestr(info, open(p, "rb").read())
pack(os.path.join(out, "stage-installer"), "installer.ipa")
pack(os.path.join(out, "stage-suite"), "LiteSuite.ipa")
pack(os.path.join(out, "stage-remove"), "LiteboardRemove.ipa")
EOF
rm -f "$OUT/lbunzip"
rm -rf "$OUT/stage-installer" "$OUT/stage-suite" "$OUT/stage-remove" "$OUT/LiteKB.appex"
(cd "$OUT" && shasum -a 256 LiteSuite.ipa > LiteSuite.ipa.sha256)
ls -l "$OUT"
