# Desk Check

A macOS menu bar app (Swift Package, no Xcode project) that reads where your eyes are through the webcam and says, in centimetres, how to move your screen and desk. `README.md` describes what it does and its privacy promises.

## The gate

Run `scripts/check.sh` before every pull request. The pull request workflow is meant to run this same script, so a pass here is a pass there. It stops at the first failing step and names it:

1. `swift format lint --strict --recursive Sources Tests` (style: `.swift-format`; fix with `swift format -i --recursive Sources Tests`)
2. `swift test`
3. `sh scripts/test-next-version.sh` (the release version rules)
4. `scripts/build-app.sh 0.0.0-ci <temp folder>` (real build, signed ad hoc with the sandbox entitlements)
5. `Tests/verify-app.sh <app>` (permissions the README promises)
6. `Tests/verify-wrapper.sh <app> 0.0.0-ci` (`desk-check --version` and the launcher)

`Tests/sandbox-probe.sh` is not part of the gate. It runs the sandbox against your real `~/.config/desk-check`; run it by hand after changing `Resources/DeskCheck.entitlements` or settings-file code.

## Conventions

- Commit subjects are `type(scope): summary` with `feat`, `fix`, `chore`, `test`, `refactor`, `docs` or `perf`. `scripts/next-version.sh` turns `feat`, `fix` and breaking commits into a release on each merge to main, so never label a fix as a feature.
- Keep logic in `Sources/DeskCheckCore` where tests can reach it; `Sources/DeskCheck` is the app shell.
- `.architecture.json` maps the parts, links and state machines; update it when a change moves any of them.
