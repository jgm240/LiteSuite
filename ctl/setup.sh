#!/bin/sh
# Run as root: sh <LiteBoard.app>/ctl/setup.sh enable|disable|permanent|update|refresh
#   enable     swap now; undone by a reboot or `disable`
#   permanent  like enable, and also swap at every boot where the jailbreak is active.
#              The rootfs is NOT modified: without the jailbreak, stock SpringBoard boots.
#   update     install /var/tmp/liteboard-update.ipa over this app (used by the in-app updater)
#   refresh    re-copy the control scripts and fix permissions; changes nothing else
# Uses only shell builtins plus cp/mv/mkdir/chmod/chown/launchctl: `id`, `dirname`, `sed`,
# `find` and `date` are missing on minimal jailbreaks.

case "$0" in
*/*) D=$(cd "${0%/*}" && pwd) ;;
*)   D=$(pwd) ;;
esac
APP=${D%/*}

# root can write /var/root; mobile cannot
[ -w /var/root ] || { echo "run as root"; exit 1; }

# Progress goes to the screen/app and to a file next to the crash reports (fetchable over USB).
SETUPLOG=/var/mobile/Library/Logs/CrashReporter/LiteBoard-setup.ips
say() { echo "$*"; echo "$*" >> "$SETUPLOG" 2>/dev/null; }
say "setup.sh $1 from $APP"

case "$1" in
enable|disable|permanent|update|refresh|dump) ;;
*) echo "usage: setup.sh enable|disable|permanent|update|refresh|dump"; exit 1 ;;
esac

if [ "$1" = dump ]; then
	# What the real SpringBoard/backboardd are entitled to, and their launchd job settings; fetch with
	# `idevicecrashreport -e -k <dir>` (file lands in the crash-report folder).
	OUT=/var/mobile/Library/Logs/CrashReporter/LiteBoard-system.ips
	LB="$APP/LiteBoard"
	{
		echo "LiteBoard system dump"
		ls -l /System/Library/CoreServices/SpringBoard.app/SpringBoard /usr/libexec/backboardd 2>&1
		for b in /System/Library/CoreServices/SpringBoard.app/SpringBoard /usr/libexec/backboardd; do
			echo "=== entitlements: $b"; "$LB" --entitlements "$b" 2>&1
		done
		for f in /System/Library/LaunchDaemons/com.apple.SpringBoard.plist /System/Library/LaunchDaemons/com.apple.backboardd.plist; do
			echo "=== launchd plist: $f"; "$LB" --plist "$f" 2>&1
		done
	} > "$OUT" 2>&1
	chmod 644 "$OUT"
	say "system dump written to $OUT"
	exit 0
fi

if [ "$1" = update ]; then
	IPA=/var/tmp/liteboard-update.ipa
	T=/var/tmp/lbupdate.$$
	[ -f "$IPA" ] || { echo "no update file"; exit 1; }
	[ -x "$APP/LiteBoard" ] || chmod 755 "$APP/LiteBoard"
	rm -rf "$T"; mkdir -p "$T" || exit 1
	"$APP/LiteBoard" --unzip "$IPA" "$T" || { rm -rf "$T" "$IPA"; echo "unzip failed"; exit 1; }
	NEW="$T/Payload/LiteBoard.app"
	[ -f "$NEW/LiteBoard" ] || { rm -rf "$T" "$IPA"; echo "not a LiteBoard IPA"; exit 1; }
	case "$APP" in
	/Applications/*) OWNER=root:wheel ;;
	*)               OWNER=mobile:mobile ;;
	esac
	chown -R "$OWNER" "$NEW"
	rm -rf "$APP.old"
	mv "$APP" "$APP.old" || { rm -rf "$T" "$IPA"; echo "cannot move old app"; exit 1; }
	if ! mv "$NEW" "$APP"; then
		mv "$APP.old" "$APP"   # roll back
		rm -rf "$T" "$IPA"
		echo "install failed, old version restored"; exit 1
	fi
	rm -rf "$APP.old" "$T" "$IPA"
	# Hand over to the new copy so it re-installs its own scripts and fixes permissions.
	exec sh "$APP/ctl/setup.sh" refresh
fi

mkdir -p /Library/LiteBoard || exit 1
cp "$D"/Library/LiteBoard/*.plist /Library/LiteBoard/ || exit 1
# GraphicsServices checks in "<bundle id>.gsEvents" (and, as SpringBoard, PurpleSystemEventPort).
# launchd refuses (error 1100) any name the job does not declare, so declare every candidate.
# The real bundle id differs per installer (re-signing adds a suffix), so ask the binary.
# The daemon runs from a copy at a fixed path: reinstalling the IPA gives the app a new container
# path and moves the old one to installd's "Dead" folder, which left the daemon pointing at nothing.
STABLE=/Library/LiteBoard/LiteBoard.app
rm -rf "$STABLE.new"
cp -R "$APP" "$STABLE.new" || { say "copy of the app failed"; exit 1; }
# Replace the installer's re-signed binary with the original, which carries LiteBoard's entitlements
# (backboardd refuses clients without com.apple.backboard.client).
if "$APP/LiteBoard" --inflate "$D/LiteBoard.z" "$STABLE.new/LiteBoard"; then
	say "restored the original entitlement-signed binary"
else
	say "could not restore the signed binary; the daemon will run the installer's re-signed copy"
fi
rm -rf "$STABLE" && mv "$STABLE.new" "$STABLE" || { say "could not place $STABLE"; exit 1; }
chmod 755 "$STABLE/LiteBoard"
ID=$("$STABLE/LiteBoard" --bundle-id 2>/dev/null)
[ -n "$ID" ] || { say "the copied LiteBoard cannot read its own bundle id; not swapping SpringBoard"; exit 1; }
say "stable copy ok, bundle id $ID"
IDSERVICE=""
[ -n "$ID" ] && IDSERVICE="<key>$ID.gsEvents</key><true/>"
# Point the daemon at this install's real binary path.
cat > /Library/LiteBoard/com.liteboard.daemon.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.liteboard.daemon</string>
	<key>ProgramArguments</key>
	<array>
		<string>$STABLE/LiteBoard</string>
	</array>
	<key>UserName</key>
	<string>root</string>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>ThrottleInterval</key>
	<integer>5</integer>
	<key>EnvironmentVariables</key>
	<dict>
		<key>LITEBOARD_REPLACE</key>
		<string>1</string>
	</dict>
	<key>MachServices</key>
	<dict>
		<key>PurpleSystemEventPort</key><true/>
		<key>com.apple.springboard.gsEvents</key><true/>
		<key>com.liteboard.app.gsEvents</key><true/>
		$IDSERVICE
	</dict>
	<key>StandardErrorPath</key>
	<string>/var/mobile/Library/Logs/CrashReporter/LiteBoard-stderr.ips</string>
</dict>
</plist>
EOF
cp "$D"/usr/bin/liteboardctl /usr/bin/ || exit 1
cp "$D"/usr/libexec/liteboard-watchdog "$D"/usr/libexec/liteboard-boot /usr/libexec/ || exit 1
chmod 755 /usr/bin/liteboardctl /usr/libexec/liteboard-watchdog /usr/libexec/liteboard-boot
chown root:wheel /Library/LiteBoard/*.plist

say "daemon plist and scripts installed"
# Make the in-app button work from now on, even if the installer didn't keep setuid.
chown root:wheel "$APP/lbroot" && chmod 6755 "$APP/lbroot"

if [ "$1" = refresh ]; then
	(uicache >/dev/null 2>&1 &)
	exit 0
fi

if [ "$1" = permanent ]; then
	cp "$D/Library/LiteBoard/com.liteboard.boot.plist" /Library/LaunchDaemons/ || exit 1
	chown root:wheel /Library/LaunchDaemons/com.liteboard.boot.plist
	chmod 644 /Library/LaunchDaemons/com.liteboard.boot.plist
	exec /usr/bin/liteboardctl enable
fi

exec /usr/bin/liteboardctl "$1"
