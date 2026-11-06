# Desk Check

Command-Z for your desk: a macOS menu bar app that uses your webcam to tell you, in
centimetres, how to move your screen and desk, and remembers your sitting and standing
desk heights so you can always go back to your favourite setting.

> **Status:** early. Desk Check checks your screen distance and height with the webcam,
> remembers sit and stand desk heights, and has a live mode for cranking the desk.
> Chair advice is not built yet.

## What it does

Press **Check posture** in the menu bar popover. The camera opens for about two seconds,
finds your eyes with Apple's Vision face landmarks, closes again, and gives one sentence
per adjustment, each with a number:

- Screen distance, aiming for 50 to 70 cm from your eyes: "Move the screen 12 cm closer."
- Screen height, aiming for your eyes 0 to 10 cm above the top edge:
  "Lower the screen by 8 cm."

Distance comes from how far apart your eyes look in the frame; height from where they sit
relative to the lens, plus the lens's height above the top of the screen. Both are
estimates until you give Desk Check tape measurements and calibrate your webcam.

### Setups

A setup is one place you use Desk Check, for example a standing desk with an external
webcam and screen, and a MacBook on a normal desk. Each setup has its own camera, screen
label, tape measurements, lens offset and list of what you can move. The popover shows a
picker when there is more than one, and Desk Check remembers the one you used last.
**Settings** can add (from an external or a MacBook template), rename, duplicate and
delete setups. The MacBook template is seated only: desk height and screen height are
fixed, so it has no standing preset and advice reports screen height instead of telling
you to move it.

Switching setups automatically is optional (`auto_switch = true`): Desk Check moves to the
setup that fits when a webcam is plugged in or unplugged. Reacting to the lid opening or
closing is not built yet.

### Settings

Open **Settings…** from the popover. All lengths are in centimetres, and an empty field
means the default estimate applies:

| Setting | Meaning | Default |
| --- | --- | --- |
| Camera | automatic (external if plugged in), the MacBook's, or a webcam by name | automatic |
| Eye to screen | tape measure, seated as you normally sit; used to calibrate | none |
| Top of screen above desk | tape measure | 45 (24 for the MacBook) |
| Webcam lens above screen top | tape measure | 1 (0.5 for the MacBook) |
| Your height | tape measure | 175 |
| Seated eyes above desk | tape measure; used to calibrate the webcam's tilt | 23% of your height |
| Eyes to elbow | tape measure, the same sitting or standing; live mode uses it for desk height | 30% of your height |
| Sit and stand desk height | floor to the top of the desk, read from the tape on the desk leg (stand is absent when desk height is fixed) | none |
| Screen height, screen distance, desk height, chair height | adjustable or fixed | adjustable |

A side-view drawing above the tape measure fields shows what to measure. The field you are
in, or hover over, lights its line and caption; click a line to jump to its field. Your height,
Eyes to elbow and Stand switch it to a standing drawing, and a MacBook setup draws a laptop.

**Calibrate webcam** sits at your tape distance and stores, per webcam name, its field of
view and tilt. Calibration belongs to the camera, not the setup, so every setup using that
camera shares it, and deleting a setup keeps it. Without calibration a typical 70 degree
field of view is assumed, which can be a few centimetres off. The optional preview shows
the camera picture with the detected eye points while a check runs; the picture is held in
memory only.

Chair height is stored but does not change advice yet.

### Desk presets

Presets belong to a setup. In Settings, type the desk height you read on the tape stuck to
the desk leg for **Sit** and **Stand**. Set the desk to that height, then press
**Remember view** in the popover: the camera stores how far the screen is and where your
eyes sit against it. Later, set the desk to the tape reading and press **Confirm**; the
camera checks the view is within 3 cm of what you saved and says what is off if not.
Changing the tape height forgets the remembered view. A setup with a fixed desk (the
MacBook template) has a sit preset only.

### Live mode

**Live** in the popover opens a small window that stays on top. The camera runs while it
is open and turns off when you close it, press Stop, or after 10 minutes. Readings are
averaged over about a second, so the number follows your cranking without flicker.
Each adjustment you can move gets a row with a colour, an arrow and the centimetres to move:

| Adjustment | Target | Green | Yellow |
| --- | --- | --- | --- |
| Screen height | top of screen 2 cm below eye level | within 3 cm | within 6 cm |
| Screen distance | 62 cm from the eyes | within 12 cm | within 20 cm |
| Desk height | desk surface 3 cm below your elbow | within 3 cm | within 6 cm |

Beyond yellow is red. Fixed adjustments get no row, so the MacBook setup shows distance only.

Accuracy target: within 3 cm for distance and 2 cm for eye height compared with a tape
measure, sitting and standing, after calibration. That has to be checked at your own desk;
see [Checking accuracy](#checking-accuracy).

### Checking accuracy

Do this once for each setup you use, for example the standing desk and the MacBook.

1. Pick the setup, sit, enter its measurements and calibrate. Check posture.
2. Compare the reported distance with a tape measure from your eyes to the screen, and the
   reported "eyes above the top edge" with a tape against the screen's top edge.
3. Stand and compare again. Move the screen exactly 5 cm and check that the reading
   changes by 5 cm, within the limits above. A MacBook setup is seated only, so skip
   the standing reading there and move the laptop 5 cm instead.
4. Switch to the other setup in the popover and confirm it reads its own camera and
   measurements, not the first setup's.

## Install

```sh
brew install marcellovictorino/tap/desk-check
desk-check
```

Homebrew builds Desk Check on your Mac with Apple's command line tools, which Homebrew
already needs; Xcode is not required. The app built this way is signed for your Mac
only, so macOS opens it without a warning and no Apple developer account is involved.

Desk Check lives in the menu bar and has no Dock icon. To find it in Spotlight too:

```sh
ln -sf "$(brew --prefix)/opt/desk-check/DeskCheck.app" ~/Applications/
```

Requires macOS 14 or later on Apple silicon.

Coming from Desk Undo: `brew uninstall desk-undo`, then install `desk-check`. The tap keeps `desk-undo`
as an alias that installs Desk Check.

After each `brew upgrade`, macOS asks for the camera once more; see
[Camera permission and upgrades](#camera-permission-and-upgrades).

## Privacy

- The camera runs only while a check runs. It is off the rest of the time.
- No image is ever saved. The app keeps numbers only, on your Mac.
- No network access at all. The App Sandbox denies every connection: the app does not
  have the network permission.
- The only folder outside its own container that Desk Check may read or write is
  `~/.config/desk-check/`, where `config.toml` lives.

You can read these permissions back from the installed app yourself:

```sh
codesign -d --entitlements - "$(brew --prefix)/opt/desk-check/DeskCheck.app"
```

## Camera permission and upgrades

macOS asks for the camera the first time a check runs. After `brew upgrade` it asks
**once more**: Homebrew rebuilds the app, and macOS ties the permission to the exact
build when an app is signed for one Mac rather than with a developer account. Click
Allow and the new build keeps it until the next upgrade.

Tested on macOS 27 with Homebrew 7: 0.1.0 asked, was allowed and counted frames; after
upgrading to 0.1.1 the permission read "not asked yet" again and macOS asked again.

## Configuration

Settings live in `~/.config/desk-check/config.toml`, a plain text file that allows
comments, so it can sit in your dotfiles. The app writes a commented starter file on
first launch. Desk Check was called Desk Undo before version 0.2. If `~/.config/desk-undo/config.toml`
exists and the new file does not, the first launch copies it across and leaves the old folder alone,
so you can delete it yourself once you are happy. Settings edits only the lines it changes, so your own comments stay. Each setup is a
`[setups."<name>"]` table, which you can also copy by hand. Webcam calibration lives in
one `[webcams."<camera name>"]` table per webcam.

## Build from source

```sh
scripts/build-app.sh 0.1.0 .build/app     # builds and signs .build/app/DeskCheck.app
open .build/app/DeskCheck.app
```

To build with the command line tools even when Xcode is installed, prefix the command
with `DEVELOPER_DIR=/Library/Developer/CommandLineTools`.

## Tests

```sh
Tests/verify-app.sh .build/app/DeskCheck.app   # reads the permissions back from the built app
swift test                                     # geometry, advice and config tests (needs Xcode)
Tests/sandbox-probe.sh                         # runs a probe under the app's sandbox rules
scripts/test-formula-locally.sh 0.1.0          # installs through a local test tap
swift Tests/camera-in-use.swift                # lists cameras in use; exits 1 if any is on
open "$(brew --prefix)/opt/desk-check/DeskCheck.app" --args --check   # one check at launch
```

`verify-app.sh` fails if the app gains a Dock icon, loses the camera text, leaves the
sandbox, or gains network access or any other folder. `sandbox-probe.sh` signs a small
program with the app's own entitlements and checks, through the kernel, that the config
folder works while the rest of the home folder and the network are refused. The probe
creates `~/.config/desk-check/` if it is missing, and macOS keeps an empty container for
it in `~/Library/Containers/`.

## Credits

Desk Check is inspired by [Posturr](https://github.com/tldev/dorso) (now Dorso) by tldev,
a macOS app that blurs your screen when you slouch. Desk Check shares no code with it.

This is general guidance, not medical advice.

## Licence

[MIT](LICENSE)
