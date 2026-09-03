# MiniCam Public GitHub Release Implementation Plan

## Objective

Publish MiniCam source code and a downloadable universal macOS beta safely, with bilingual documentation, complete license notices, and a reproducible verified release package.

## Tasks

### 1. Audit repository safety and release inputs

- Check tracked files and Git history for credentials, authenticated URLs, keys, tokens, private media, databases, logs, and personal paths.
- Inspect repository visibility and existing GitHub metadata without changing remote state.
- Confirm dependency versions, licenses, app version, deployment target, architectures, and bundle identifier.
- Stop before publication if sensitive history or unresolved licensing issues are found.

### 2. Prepare public repository documentation

- Replace the existing README with an English public-facing guide.
- Add an equivalent `README.ru.md`.
- Add the MIT `LICENSE` file.
- Complete `THIRD_PARTY_NOTICES.md` with versions, source locations, and distribution notes.
- Add `CHANGELOG.md` for `0.1.0-beta.1`.
- Replace personal network examples with documentation-only addresses.
- Update `.gitignore` for all local build, cache, log, snapshot, and event-data locations.

### 3. Add repeatable release packaging

- Add a small release-packaging script under `Tools/`.
- Require an existing verified Release app as input rather than hiding the Xcode build command.
- Copy `MiniCam.app` and license notices into a staging directory.
- Create a macOS-safe ZIP with `ditto` and generate `SHA256SUMS.txt`.
- Keep generated release artifacts ignored by Git.

### 4. Verify the release candidate

- Run the focused unit-test suite once.
- Perform a clean universal Release build.
- Verify app, VLCKit, and FFmpeg architectures and the macOS 12 deployment target.
- Verify the ad-hoc signature before and after extracting the ZIP.
- Launch the extracted application for a smoke check.
- Validate documentation filenames, versions, and checksum.

### 5. Review and publish

- Commit publication-readiness changes without generated binaries.
- Present README, changed files, release notes, artifact size, checksum, and verification results to the user.
- After explicit approval, push the commit, make the GitHub repository public if required, tag `v0.1.0-beta.1`, and create a GitHub prerelease with the ZIP and checksum.

## Boundaries

- Do not change playback, archive, detection, export, or camera behavior.
- Do not rewrite Git history without explicit approval.
- Do not disable Gatekeeper in user instructions.
- Do not commit generated applications or release ZIP files to the source repository.
