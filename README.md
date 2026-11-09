# Desk Check

Command-Z for your desk: a macOS menu bar app that uses your webcam to tell you, in
centimetres, how to move your screen and desk, and remembers your sitting and standing
desk heights so you can always go back to your favourite setting.

> **Status:** early. Desk Check checks your screen distance and height with the webcam,
> remembers sit and stand desk heights, and has a live mode for cranking the desk.
> Chair advice is not built yet.

## What it does

Press **Check desk** in the menu bar popover. The camera opens for about two seconds,
finds your eyes with Apple's Vision face landmarks, closes again, and gives one sentence
per adjustment, each with a number:

- Screen distance, aiming for 50 to 70 cm from your eyes: "Distance: move the screen 15 cm further away."
- Screen height, aiming for your eyes 0 to 10 cm above the top edge:
  "Screen: lower 8 cm."

Distance comes from how far apart your eyes look in the frame; height from where they sit
relative to the lens, plus the lens's height above the top of the screen. Both are
estimates until you give Desk Check tape measurements and calibrate your webcam.

### Setups

A setup is one place you use Desk Check, for example a standing desk with an external
webcam and screen, and a MacBook on a normal desk. Each setup has its own camera, screen
label, tape measurements, lens offset and list of what you can move. The popover shows a
picker when there is more than one, and Desk Check remembers the one you used last.
The popover's gear opens Settings and the power icon quits. On macOS 26 and later the buttons and rows use Liquid Glass; macOS 14 and 15 get the standard bordered buttons and plain tinted rows. Settings sections use a translucent material on every version.
**Settings** can add (from an external or a MacBook template), rename, duplicate and
delete setups. The MacBook template is seated only: desk height and screen height are
fixed, so it has no standing preset and advice reports screen height instead of telling
you to move it.

Switching setups automatically is optional (`auto_switch = true`): Desk Check moves to the
setup that fits when a webcam is plugged in or unplugged. Reacting to the lid opening or
closing is not built yet.

### Settings

Click the gear in the popover. Settings replace the popover's content, with the desk drawing pinned above the fields; Esc or Back returns to the main view, and Esc again or a click away closes the popover. All lengths are in centimetres, and an empty field
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

**Live** in the popover swaps the popover to the live view, with Stop in its header. The
camera runs while it shows and turns off when you press Stop or Esc (both return to the main view,
where Esc or a click away closes the popover), when you click away so the popover closes, or after 10 minutes. Readings are
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

1. Pick the setup, sit, enter its measurements and calibrate. Check desk.
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

After each `brew upgrade`, macOS asks for the camera once more; see
[Camera permission and upgrades](#camera-permission-and-upgrades).

## Privacy

- The camera runs only while a check runs. It is off the rest of the time.
- The app never saves camera images. It keeps numbers only, on your Mac. The offscreen
  tests below save pictures of the interface with starter settings, not camera frames.
- No network access at all. The App Sandbox denies every connection: the app does not
  have the network permission.
- Desk Check defaults to `~/.config/desk-check/config.toml`. **Choose settings file…** in Settings grants read/write access to another file; an app-scoped bookmark remembers that permission after relaunch. You can change the chosen file later.
- On first launch with no chosen file, Desk Check can also read `~/.config/desk-undo/config.toml` to migrate settings; it never writes to the old folder.

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

Settings default to `~/.config/desk-check/config.toml`, a plain text file that allows
comments. The app writes a commented starter file on first launch when no file has been chosen.
Use **Choose settings file…** at the top of Settings to pick an existing `.toml` file elsewhere, or change the choice later.
If your default file is a symlink managed by a dotfiles project, choose its actual target file in that project: the default folder permission cannot grant access outside that folder.
Desk Check remembers the permission and uses the chosen file for setup edits, calibration and Live.
Changing files discards unsaved form edits; cancelling the picker leaves the current choice unchanged.
If the file or its saved permission cannot be read, Settings and the main view show a warning.
Saving and camera checks remain unavailable until settings load; choose the file again to recover. Desk Check was called Desk Undo before version 0.2. If `~/.config/desk-undo/config.toml`
exists and the new file does not, the first launch copies it across and leaves the old folder alone,
so you can delete it yourself once you are happy. Settings edits only the lines it changes, so your own comments stay. Each setup is a
`[setups."<name>"]` table, which you can also copy by hand. Webcam calibration lives in
one `[webcams."<camera name>"]` table per webcam.

## Build from source

```sh
scripts/build-app.sh 0.3.0 .build/app     # builds and signs .build/app/DeskCheck.app
open .build/app/DeskCheck.app
```

To build with the command line tools even when Xcode is installed, prefix the command
with `DEVELOPER_DIR=/Library/Developer/CommandLineTools`.

## Tests

```sh
Tests/verify-app.sh .build/app/DeskCheck.app   # reads the permissions back from the built app
swift test                                     # core tests and offscreen view pictures (needs Xcode)
Tests/sandbox-probe.sh                         # runs a probe under the app's sandbox rules
scripts/test-formula-locally.sh 0.3.0          # installs through a local test tap
swift Tests/camera-in-use.swift                # lists cameras in use; exits 1 if any is on
open "$(brew --prefix)/opt/desk-check/DeskCheck.app" --args --check   # one check at launch
```

### Offscreen view pictures

```sh
pictures=$(mktemp -d /tmp/desk-check-pictures.XXXXXX)
DESK_CHECK_IMAGE_DIR="$pictures" swift test --filter ViewImageTests
```

The view test saves `popover.png`, `live.png`, `settings.png`, `load-warning.png` and
`settings-warning.png` for review cards, plus `captures.json` with each picture's renderer and limitations. Every picture carries its
own omission caption so the limits remain visible when it is attached to a card.

These are **partial offscreen renders**, not desktop screenshots or proof of native glass
fidelity. The popover and Live use SwiftUI's image renderer after hidden host layout;
Settings uses a bitmap of the actual hosted view because the image renderer cannot draw
its native form. The tests never activate the app, order a window on screen, control the
mouse or start the camera. They use light appearance and starter settings, not your config.

- Popover omits outer chrome and the desktop backdrop. Camera and permission checks do not run.
- Live omits outer chrome and the desktop backdrop. Its camera-off state has no readings or coloured bands.
- Settings omits native glass button surfaces and some icons. It shows the desk drawing
  and initial form viewport, not the lower fields or outer popover chrome.

Choose a fresh output folder: the test refuses to overwrite existing files. Without
`DESK_CHECK_IMAGE_DIR`, it creates a unique temporary folder and prints its path.
Assertions check dimensions, PNG read-back, non-uniform content before captioning and
hidden/non-key windows. They do not assert complete controls, glass fidelity or interaction,
and do not compare against reference pictures. No camera images are saved.

`verify-app.sh` checks the app's Dock, camera, network, selected-file, bookmark and folder permissions. `sandbox-probe.sh`
signs a small program with the app's entitlements and checks through the kernel that Desk Check
can write its current settings folder, read the legacy folder without writing to it, and cannot
access other home folders or the network. The probe creates `~/.config/desk-check/` if needed;
macOS keeps an empty container for it in `~/Library/Containers/`.

### Isolated settings permission check

```sh
# Requires consent for ad hoc signing; use a fresh output folder.
sh Tests/build-settings-sandbox-app.sh /tmp/desk-check-settings-test-new
open /tmp/desk-check-settings-test-new/SettingsSandbox.app
```

This harness uses the real Settings controls and configuration owner in a normal test window,
with a unique app identity, isolated preferences and a container-local default file.
It does not open personal settings or start the camera. Choose a disposable TOML file outside
its container, rename a setup and save, quit and relaunch the same test app, then check the name
and save again. Choose a second file and cancel a subsequent choice; verify that only the selected
file changes. Make the chosen file unreadable and relaunch: the warning must appear and saving
must be unavailable. Choose a readable file to recover. This checks native sandbox permission;
the unit tests alone do not.

## Credits

Desk Check is inspired by [Posturr](https://github.com/tldev/dorso) (now Dorso) by tldev,
a macOS app that blurs your screen when you slouch. Desk Check shares no code with it.

This is general guidance, not medical advice.

## Licence

[MIT](LICENSE)
