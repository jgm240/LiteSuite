# LiteBoard: experimental SpringBoard replacement for iPad 4 / iOS 10.x

**Status: untested.** I could not compile or run this (no Theos or device in the authoring environment). Treat it as a starting point, and expect to debug on device.

## What it is
- A small UIKit app: opaque black background, plain scrolling icon grid, lazy cached icons. No wallpaper, blur, Spotlight, widgets, folders, or notification center.
- **Stage 1 (safe):** runs as a normal app under stock SpringBoard. It lists apps and launches them through LaunchServices.
- **Stage 2 (experimental):** `liteboardctl enable` unloads SpringBoard's launchd job and runs LiteBoard as root in its place. In this mode LiteBoard launches apps itself (fork, drop to uid 501, exec, with `HOME` set to the app's data container) and uses the home button (via IOHID) to kill the foreground app and return to the grid.

## Safety design
- Nothing is persisted: the daemon plists live in `/Library/LiteBoard`, not `/Library/LaunchDaemons`, and `launchctl -w` is never used. **A reboot always brings back stock SpringBoard** (the 10.x jailbreaks for this device are semi-untethered anyway).
- A watchdog (`com.liteboard.watchdog`) restores SpringBoard if LiteBoard doesn't write `/var/run/liteboard.alive` within 30s of enabling, or stops refreshing it for 15s.
- Manual escape over SSH: `liteboardctl disable`.

## Known risks / gaps
- iOS 10 app launching normally goes through SpringBoard's FrontBoard services. Direct exec skips the sandbox container setup and scene hand-off, so some apps may crash, show a black screen, or not receive touches. That is the core experimental question.
- No status bar, no app switcher, no lock screen, no Control Center, no notifications, and no rotation handling in replace mode.
- The entitlement list and IOHID usage values (consumer page 0x0C / usage 0x40) are best guesses; verify on device (`/var/log/liteboard.log`, `log`/`idevicesyslog`).

## Build setup (macOS)
Modern Xcode no longer ships a 32-bit iOS SDK, so use Theos with an old SDK.

```bash
brew install ldid dpkg make
git clone --recursive https://github.com/theos/theos.git ~/theos
echo 'export THEOS=~/theos' >> ~/.zshrc && export THEOS=~/theos
curl -L https://github.com/theos/sdks/archive/refs/heads/master.tar.gz | tar -xz -C /tmp
cp -R /tmp/sdks-master/iPhoneOS10.3.sdk ~/theos/sdks/   # check the name; any 10.x SDK works
```

The iPad 4 is armv7/armv7s (32-bit), so the Makefile builds `armv7`. If your current Xcode's clang refuses to target armv7, use an older Xcode toolchain (13.x) or Theos's Linux toolchain.

```bash
cd LiteBoard
chmod +x layout/usr/bin/liteboardctl layout/usr/libexec/liteboard-watchdog layout/DEBIAN/postinst
gmake package
scp packages/*.deb root@<ipad-ip>:/tmp/        # default password: alpine (change it)
ssh root@<ipad-ip> 'dpkg -i /tmp/com.liteboard.app_*.deb && uicache'
```

## Try it
1. Open **LiteBoard** from the home screen (stage 1). Confirm the grid shows and apps launch.
2. Keep an SSH session open, then:
   ```bash
   liteboardctl enable
   ```
3. If the screen is dead or wrong, run `liteboardctl disable` over SSH, wait for the watchdog, or reboot.

## Permanent mode
**Permanent...** in `installer.ipa` shows:

> !!! THIS STARTS LITEBOARD AT EVERY BOOT !!!
> !!! THIS ONLY WORKS ON UNTETHERED JBS, E.G SOCKET !!!

It installs `/Library/LaunchDaemons/com.liteboard.boot.plist`, which runs `liteboardctl enable` ~20s after boot. The rootfs is not modified: if the jailbreak is not running, the job never loads and stock SpringBoard boots. The watchdog writes `/Library/LiteBoard/disabled` if LiteBoard fails to start, which keeps the boot job off until `liteboardctl enable` is run. `LiteboardRemove.ipa` removes the job.

An earlier version renamed `SpringBoard` to `SpringBoard.bak` on the rootfs. That is gone because a modified SpringBoard cannot boot without the jailbreak (it left an iPad stuck on the Apple logo).

## LiteKB (keyboard)
`out/LiteSuite.ipa` installs LiteBoard plus **LiteKB**, a minimal keyboard extension embedded at `LiteBoard.app/PlugIns/LiteKB.appex`. Enable it in Settings > General > Keyboard > Keyboards > Add New Keyboard > LiteKB (run `uicache` if it does not appear).

It has letters, numbers and symbols pages, shift with caps lock, hold-to-repeat delete, a globe key, and light/dark themes. It deliberately has no autocorrect, prediction, key popups, haptics, images or Auto Layout, so it stays small and fast. Removing LiteBoard (LiteboardRemove.ipa) removes the keyboard too, since it lives inside the app.

## Settings and updater (v0.2.0)
Open LiteBoard and tap the gear in the top-right corner:
- **LiteKB buttons:** corner radius, key size (60-150%) and font size. Saved to `/var/mobile/Library/Preferences/com.liteboard.litekb.plist`; the keyboard reads it each time it appears.
- **Updates:** checks the latest GitHub release of `jgm240/LiteSuite`, downloads `LiteSuite.ipa`, verifies its SHA-256 (from the release's `digest`), and swaps the installed app and keyboard as root. Not available while LiteBoard is the home screen.
- **SpringBoard:** offers Temporary / Permanent replacement again.

LiteKB: long-press a key for accents and diacritics, swipe along the space bar to move the cursor.

### Publishing a release
```bash
./build.sh
gh release create v0.2.0 out/LiteSuite.ipa out/LiteSuite.ipa.sha256 --repo jgm240/LiteSuite --title v0.2.0
```
The tag must be higher than the installed `CFBundleShortVersionString` (Resources/Info.plist) and the asset must be named `LiteSuite.ipa`.

### Debugging a failed home-screen swap
LiteBoard logs its stages to `/var/log/liteboard.log` (`main:` then `didFinishLaunching reached`). If the watchdog restores SpringBoard it saves `/var/mobile/liteboard-last.log` and `/var/mobile/liteboard-launchctl.txt`.
