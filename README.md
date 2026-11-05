# Desk Undo

Command-Z for your desk: a macOS menu bar app that uses your webcam to tell you, in
centimetres, how to move your screen and desk, and remembers your sitting and standing
desk heights so you can always go back to your favourite setting.

> **Status:** early. This version proves the packaging: Homebrew builds the app on your
> Mac, the sandbox holds, and the camera opens on request. The posture check and the
> sit and stand presets come next.

## Install

```sh
brew install marcellovictorino/tap/desk-undo
desk-undo
```

Homebrew builds Desk Undo on your Mac with Apple's command line tools, which Homebrew
already needs; Xcode is not required. The app built this way is signed for your Mac
only, so macOS opens it without a warning and no Apple developer account is involved.

Desk Undo lives in the menu bar and has no Dock icon. To find it in Spotlight too:

```sh
ln -sf "$(brew --prefix)/opt/desk-undo/DeskUndo.app" ~/Applications/
```

Requires macOS 14 or later on Apple silicon.

After each `brew upgrade`, macOS asks for the camera once more; see
[Camera permission and upgrades](#camera-permission-and-upgrades).

## Privacy

- The camera runs only while a check runs. It is off the rest of the time.
- No image is ever saved. The app keeps numbers only, on your Mac.
- No network access at all. The App Sandbox denies every connection: the app does not
  have the network permission.
- The only folder outside its own container that Desk Undo may read or write is
  `~/.config/desk-undo/`, where `config.toml` lives.

You can read these permissions back from the installed app yourself:

```sh
codesign -d --entitlements - "$(brew --prefix)/opt/desk-undo/DeskUndo.app"
```

## Camera permission and upgrades

macOS asks for the camera the first time a check runs. After `brew upgrade` it asks
**once more**: Homebrew rebuilds the app, and macOS ties the permission to the exact
build when an app is signed for one Mac rather than with a developer account. Click
Allow and the new build keeps it until the next upgrade.

Tested on macOS 27 with Homebrew 7: 0.1.0 asked, was allowed and counted frames; after
upgrading to 0.1.1 the permission read "not asked yet" again and macOS asked again.

## Configuration

Settings live in `~/.config/desk-undo/config.toml`, a plain text file that allows
comments, so it can sit in your dotfiles. The app writes a commented starter file on
first launch.

## Build from source

```sh
scripts/build-app.sh 0.1.0 .build/app     # builds and signs .build/app/DeskUndo.app
open .build/app/DeskUndo.app
```

To build with the command line tools even when Xcode is installed, prefix the command
with `DEVELOPER_DIR=/Library/Developer/CommandLineTools`.

## Tests

```sh
Tests/verify-app.sh .build/app/DeskUndo.app   # reads the permissions back from the built app
Tests/sandbox-probe.sh                         # runs a probe under the app's sandbox rules
scripts/test-formula-locally.sh 0.1.0          # installs through a local test tap
swift Tests/camera-in-use.swift                # lists cameras in use; exits 1 if any is on
open "$(brew --prefix)/opt/desk-undo/DeskUndo.app" --args --check-camera   # one check at launch
```

`verify-app.sh` fails if the app gains a Dock icon, loses the camera text, leaves the
sandbox, or gains network access or any other folder. `sandbox-probe.sh` signs a small
program with the app's own entitlements and checks, through the kernel, that the config
folder works while the rest of the home folder and the network are refused. The probe
creates `~/.config/desk-undo/` if it is missing, and macOS keeps an empty container for
it in `~/Library/Containers/`.

## Credits

Desk Undo is inspired by [Posturr](https://github.com/tldev/dorso) (now Dorso) by tldev,
a macOS app that blurs your screen when you slouch. Desk Undo shares no code with it.

This is general guidance, not medical advice.

## Licence

[MIT](LICENSE)
