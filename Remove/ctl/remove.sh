#!/bin/sh
# Run as root: sh <LiteboardRemove.app>/ctl/remove.sh remove
# Restores SpringBoard and deletes everything LiteBoard installed, including this app.
# Shell builtins plus rm/mv/mount/launchctl only (`id`, `dirname`, `find` may be missing).

# root can write /var/root; mobile cannot
[ -w /var/root ] || { echo "run as root"; exit 1; }
[ "$1" = remove ] || { echo "usage: remove.sh remove"; exit 1; }

SB=/System/Library/LaunchDaemons/com.apple.SpringBoard.plist
L=/Library/LiteBoard
SBDIR=/System/Library/CoreServices/SpringBoard.app
RESTART_SB=0
case "$0" in
*/*) D=$(cd "${0%/*}" && pwd) ;;
*)   D=$(pwd) ;;
esac
SELF=${D%/*}

# Delete an app bundle; for installd installs remove the whole <UUID> container dir.
rm_app() {
	case "$1" in
	/var/containers/Bundle/Application/*) rm -rf "${1%/*}" ;;
	*) rm -rf "$1" ;;
	esac
}

# Legacy: undo the old rename-based permanent install (SpringBoard.bak -> SpringBoard).
if [ -f "$SBDIR/SpringBoard.bak" ]; then
	mount -u -o rw,suid,dev / 2>/dev/null
	mv -f "$SBDIR/SpringBoard.bak" "$SBDIR/SpringBoard" && RESTART_SB=1
fi

rm -f /Library/LaunchDaemons/com.liteboard.boot.plist /usr/libexec/liteboard-boot
launchctl unload "$L/com.liteboard.daemon.plist" 2>/dev/null
launchctl unload "$L/com.liteboard.swap.plist" 2>/dev/null
command -v killall >/dev/null 2>&1 && killall -9 LiteBoard 2>/dev/null
launchctl list | grep -q com.apple.SpringBoard || launchctl load "$SB"
launchctl unload "$L/com.liteboard.watchdog.plist" 2>/dev/null

rm -rf "$L" /usr/bin/liteboardctl /usr/libexec/liteboard-watchdog \
	/var/run/liteboard.alive /var/log/liteboard.log /var/tmp/liteboard-update.ipa \
	/var/mobile/Library/Preferences/com.liteboard.litekb.plist \
	/var/mobile/liteboard-last.log /var/mobile/liteboard-launchctl.txt \
	/var/mobile/Library/Logs/CrashReporter/LiteBoard-stderr.ips /var/mobile/Library/Logs/CrashReporter/LiteBoard-launchctl.ips
for p in /Applications/LiteBoard.app /var/containers/Bundle/Application/*/LiteBoard.app; do
	[ -d "$p" ] && rm_app "$p"
done

# Delete this app last, after the UI has had time to show the result.
(sleep 8; rm_app "$SELF"; uicache; [ "$RESTART_SB" = 1 ] && killall -9 SpringBoard) >/dev/null 2>&1 &
exit 0
