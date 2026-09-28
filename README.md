# MenubarTimer

A tiny macOS menu bar countdown timer. Click the timer icon, type a duration, press Enter — the remaining time shows in the menu bar.

## Build

```bash
./build.sh
open build/MenubarTimer.app
```

Requires the Xcode Command Line Tools (`swiftc`). The build script includes a workaround for a stale `module.modulemap` that some Command Line Tools installs ship with.

## Input formats

| Input | Duration |
| --- | --- |
| `25` | 25 minutes |
| `0.5` | 30 seconds |
| `5:30` | 5 min 30 s |
| `1:05:00` | 1 h 5 min |
| `1h30m`, `90s`, `2 min` | as written |
| `1시간 20분`, `10분 30초` | as written |

When time is up, the Glass sound loops and a notification appears; pick "알람 끄기" (Stop Alarm) from the menu to silence it. The menu also has Pause/Resume, Reset, "로그인 시 자동 실행" (Launch at Login), and Quit (⌘Q).

## Launch at login

Toggle it from the app's own menu ("로그인 시 자동 실행") — no need to touch System Settings. It uses `SMAppService` (macOS 13+), so the app must be running from a stable path (e.g. `/Applications`) for the toggle to stick.

## Install

```bash
./build.sh
rm -rf /Applications/MenubarTimer.app
cp -R build/MenubarTimer.app /Applications/
codesign --force --sign - /Applications/MenubarTimer.app
open /Applications/MenubarTimer.app
```

Running the app straight from `build/` also works, but login-at-startup and Launch Services registration are keyed to the app's path, so `/Applications` is recommended for day-to-day use.
