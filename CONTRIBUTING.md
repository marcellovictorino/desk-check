# Contributing to Desk Check

Thanks for helping. Bug reports, ideas and code are all welcome.

## Report a bug or suggest a feature

1. Search [existing issues](https://github.com/marcellovictorino/desk-check/issues) first; add to
   one that matches rather than opening another.
2. Otherwise [open an issue](https://github.com/marcellovictorino/desk-check/issues/new/choose)
   and pick the bug report or feature request form.

Issues are public. Leave out personal information, camera images, private file paths and whole
settings files; share only the measurements and setup values that matter.

## Change the code

1. For anything more than a small fix, open an issue first so we can agree on the approach.
2. Follow the [development notes in the README](README.md#development) to build and test.
3. Run `scripts/check.sh` and make sure it passes. Pull requests run the same script.
4. In the pull request, explain what the change does and why, and which checks you ran.

Commit subjects follow `type(scope): summary`, using `feat`, `fix`, `chore`, `test`, `refactor`,
`docs` or `perf`. A `feat` or `fix` merged to main publishes a release, so label changes
accurately.
