# MenubarTimer

<img src="ICON/MenubarTimer.icon/Assets/Untitled.png" width="128" alt="MenubarTimer icon">

A tiny macOS menu bar countdown timer. Click the timer icon, type a duration, press Enter — the remaining time shows in the menu bar.

## Download

Grab the latest build from [Releases](https://github.com/dohywu/menubar-timer/releases/latest) — download `MenubarTimer-vX.Y.Z.zip`, unzip it, and drag `MenubarTimer.app` into `/Applications`.

The app isn't notarized by Apple, so the first launch will be blocked by Gatekeeper. To open it:

1. Right-click (or Control-click) `MenubarTimer.app` → **Open** → **Open** again in the dialog.
2. Or: System Settings → Privacy & Security → scroll down to "MenubarTimer was blocked" → **Open Anyway**.

You only need to do this once.

## Input formats

| Input | Duration |
| --- | --- |
| `25` | 25 minutes |
| `0.5` | 30 seconds |
| `5:30` | 5 min 30 s |
| `1:05:00` | 1 h 5 min |
| `1h30m`, `90s`, `2 min` | as written |
| `1시간 20분`, `10분 30초` | as written |

When time is up, the Glass sound loops and a notification is filed quietly in Notification Center (no banner popup — check the Notification Center sidebar if you want to see it). Pick "알람 끄기" (Stop Alarm) from the menu to silence it. The menu also has Pause/Resume, Reset, "로그인 시 자동 실행" (Launch at Login), and Quit (⌘Q).

## Launch at login

Toggle it from the app's own menu ("로그인 시 자동 실행") — no need to touch System Settings. It uses `SMAppService` (macOS 13+), so the app must be running from a stable path (e.g. `/Applications`) for the toggle to stick.

## Build from source

```bash
./build.sh            # builds version 1.0.0 into build/MenubarTimer.app
./build.sh 1.2.0       # or pass an explicit version
```

Requires the Xcode Command Line Tools (`swiftc`). Xcode itself is only needed if you want Notification Center to work — see below. The build script also includes a workaround for a stale `module.modulemap` that some Command Line Tools installs ship with.

### Install the local build

```bash
rm -rf /Applications/MenubarTimer.app
cp -R build/MenubarTimer.app /Applications/
open /Applications/MenubarTimer.app
```

Don't re-run `codesign` after copying — `build.sh` already signs the app (see below); signing again would overwrite that. Running the app straight from `build/` also works, but login-at-startup and Launch Services registration are keyed to the app's path, so `/Applications` is recommended for day-to-day use.

### Notification Center support

`UNUserNotificationCenter` (the API that gets the alarm into Notification Center) refuses the permission request outright — no prompt, no error dialog, just silent denial — for an app that's only ad-hoc signed. `build.sh` auto-detects a real signing identity (`security find-identity -v -p codesigning`) and uses it if one exists, falling back to ad-hoc otherwise (notifications just won't reach Notification Center in that case — the Glass sound still plays regardless).

To get a real identity, one-time setup:

1. Install Xcode (App Store) and open it.
2. Xcode → Settings → Accounts → "+" → sign in with an Apple ID (free is fine).
3. Select the new Personal Team → "Manage Certificates…" → "+" → Apple Development.
4. If `security find-identity -v -p codesigning` still shows 0 *valid* identities even though the certificate exists (`security find-identity -p codesigning` without `-v`), the Apple WWDR intermediate certificate is probably missing. Install it:
   ```bash
   curl -fsSL -o /tmp/wwdr.cer https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
   security import /tmp/wwdr.cer -k ~/Library/Keychains/login.keychain-db
   ```
   (If that generation doesn't match, try `AppleWWDRCAG2`/`G4`/`G5`/`G6` the same way — harmless to import more than one.)

Then just `./build.sh` again — it'll pick up the new identity automatically.

### App icon

`build.sh` looks for a PNG under `ICON/*.icon/Assets/` (an [Icon Composer](https://developer.apple.com/icon-composer/) package) and, if found, renders it at every size `.icns` needs and sets it as the app icon. This bypasses Icon Composer's own Xcode-asset-catalog pipeline (this isn't an Xcode project), so the gradient/shadow/translucency layers defined in `icon.json` aren't applied — only the flat PNG image. No icon source → the app just builds without a custom icon.

## Releasing a new version

```bash
VERSION=1.1.0
./build.sh "$VERSION"
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent build/MenubarTimer.app "dist/MenubarTimer-v$VERSION.zip"
git tag "v$VERSION"
git push origin "v$VERSION"
gh release create "v$VERSION" "dist/MenubarTimer-v$VERSION.zip" --title "v$VERSION" --notes "..."
```
