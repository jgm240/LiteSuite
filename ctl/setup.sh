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

case "$1" in
enable|disable|permanent|update|refresh) ;;
*) echo "usage: setup.sh enable|disable|permanent|update|refresh"; exit 1 ;;
esac

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
		<string>$APP/LiteBoard</string>
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
	<key>StandardErrorPath</key>
	<string>/var/log/liteboard.log</string>
</dict>
</plist>
EOF
cp "$D"/usr/bin/liteboardctl /usr/bin/ || exit 1
cp "$D"/usr/libexec/liteboard-watchdog "$D"/usr/libexec/liteboard-boot /usr/libexec/ || exit 1
chmod 755 /usr/bin/liteboardctl /usr/libexec/liteboard-watchdog /usr/libexec/liteboard-boot
chown root:wheel /Library/LiteBoard/*.plist

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
