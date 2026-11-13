# Desk Check

A macOS menu bar app that uses your webcam to tell you, in centimetres, how to move your
screen and desk, and remembers your sitting and standing desk heights.

> **Status:** early. Chair advice is not built yet. This is general guidance, not medical advice.

## Install

```sh
brew install marcellovictorino/tap/desk-check
desk-check
```

Requires macOS 14.5 or later on Apple silicon. Homebrew builds the app on your Mac with
Apple's command line tools, version 16 or later (Swift 6); Xcode and a developer account are not
needed. Desk Check lives in the menu bar. `desk-check --version` prints the installed version.

After each `brew upgrade`, run `desk-check` again to replace the running copy. macOS asks for
the camera once more after an upgrade, because the permission is tied to the exact build.

## What it does

- **Check desk** opens the camera for a few seconds, finds your eyes and gives one
  sentence per adjustment, for example "Screen: lower 8 cm." A spinner shows while it
  works. Pressed within 10 seconds of Live, with nothing changed, it reuses Live's
  reading instead and does not open the camera.
- **Setups** keep a camera, screen and tape measurements per place you work, such as a
  standing desk and a MacBook. Desk Check can switch setup when a webcam is plugged in.
- **Presets** remember the sit and stand desk heights you read off the desk leg, and
  confirm the view matches when you return to them.
- **Live** keeps the camera on while you crank the desk, with a green, yellow or red row
  and the centimetres to move for each adjustment.

For accurate numbers, enter your tape measurements in Settings (the gear in the popover) and
press **Calibrate webcam**.

## Settings file

Settings live in `~/.config/desk-check/config.toml`, a commented TOML file the app creates on
first launch. Settings edits only the lines it changes, so your comments stay.

To use another file, click **Choose settings file…** in Settings. Desk Check remembers that
choice and permission after relaunch.

If the default file is a symlink into a dotfiles folder (for example a Stow package's
`.config/desk-check/config.toml`), macOS will not let the sandboxed app follow it until you
allow the real file once. Settings names the file the link points to. **Choose settings file…**
opens on that file with hidden folders shown: click **Open**.

If settings cannot be read, Settings shows a warning, and saving and camera checks stay off
until a readable file is chosen.

## Privacy

- The camera runs only during a check or Live, and no images are saved.
- No network access: the App Sandbox denies every connection.
- File access is limited to the settings folder, the old `~/.config/desk-undo/` folder (read
  once, to migrate), and a file you choose.

Read the permissions back with
`codesign -d --entitlements - "$(brew --prefix)/opt/desk-check/DeskCheck.app"`.

## Development

```sh
scripts/build-app.sh 0.3.0 .build/app            # build and sign .build/app/DeskCheck.app
swift test                                       # core tests and offscreen view pictures
Tests/verify-app.sh .build/app/DeskCheck.app     # check the built app's permissions
Tests/sandbox-probe.sh                           # check the sandbox rules through the kernel
sh Tests/build-settings-sandbox-app.sh <new-dir> # disposable sandboxed Settings test app
```

`DESK_CHECK_IMAGE_DIR=<dir> swift test --filter ViewImageTests` saves partial offscreen
pictures of the popover, Live and Settings. The Settings test app saves a picture of its
window to `SettingsSandboxTest/snapshots` in its container when sent `SIGUSR1`.
Each script's header explains its use.

The tests use Swift Testing, so `swift test` works with the command line tools alone. With the
command line tools, an incremental build can sometimes fail with "plugin for module 'TestingMacros'
not found"; run the command again, or pass
`-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`.

## Credits

Inspired by [Posturr](https://github.com/tldev/dorso) (now Dorso) by tldev. Desk Check shares
no code with it.

## Licence

[MIT](LICENSE)
