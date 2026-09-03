# MiniCam Public GitHub Release Design

## Goal

Prepare MiniCam for publication as an open-source macOS application and make a tested universal beta build available from GitHub Releases. The first public version is a technical beta for users of compatible Hikvision cameras, not a promise of compatibility with every IP camera.

## Publication format

- Make the existing GitHub repository public.
- Publish the source under the MIT License.
- Create GitHub prerelease `v0.1.0-beta.1`.
- Attach `MiniCam-0.1.0-beta.1-macos-universal.zip` and `SHA256SUMS.txt`.
- Keep the Xcode marketing version at `0.1.0`; the Git tag identifies the beta iteration.
- Do not create a DMG for the first beta.
- Do not publish to the Mac App Store.

## Repository documentation

The public repository will contain:

- `README.md`: primary English documentation.
- `README.ru.md`: equivalent Russian documentation.
- `LICENSE`: MIT License for MiniCam source code.
- `THIRD_PARTY_NOTICES.md`: versions, licenses, attribution, and source locations for VLCKit, FFmpeg, and YOLOX.
- `CHANGELOG.md`: features and known limitations of `0.1.0-beta.1`.
- `ThirdPartyLicenses/`: complete applicable license texts.

The README files will describe:

- the product purpose and main capabilities;
- supported macOS versions and CPU architectures;
- tested camera hardware and required camera configuration;
- installation of the unsigned GitHub build without disabling Gatekeeper globally;
- initial camera connection and normal use;
- local-only processing and absence of telemetry or cloud services;
- building from source with Xcode and CocoaPods;
- archive, RTSP session, motion-detection, and export limitations;
- basic troubleshooting and instructions for reporting a reproducible problem.

Personal camera addresses will be replaced with documentation-only examples. Documentation will not contain credentials, private footage, event images, local paths, or identifying diagnostic data.

## Distribution package

The release ZIP will contain the universal `MiniCam.app` and the third-party notices required for binary distribution. The archive must preserve the macOS application bundle and its ad-hoc signature.

Because the project does not have an Apple Developer membership or Developer ID certificate, the release will be explicitly described as unsigned/not notarized. Installation instructions will direct users to approve this specific application through macOS Privacy & Security. They will not ask users to disable Gatekeeper globally.

## Privacy and security review

Before publication:

- inspect tracked files and Git history for credentials, authenticated RTSP URLs, private keys, tokens, personal paths, camera snapshots, databases, and logs;
- verify that generated builds, Xcode user data, screenshots, frame caches, event databases, and logs are ignored;
- retain only neutral example network addresses in tests and documentation;
- stop and request approval before rewriting Git history if sensitive data is found;
- avoid changing camera transport or playback behavior as part of release preparation.

## Verification

The release candidate must pass these checks:

- a clean Release build from the public source tree;
- the existing focused unit-test suite;
- `arm64` and `x86_64` slices in the app, VLCKit, and bundled FFmpeg;
- macOS 12 as the minimum supported version;
- valid ad-hoc bundle signature before and after ZIP extraction;
- launch of the extracted application;
- valid SHA-256 checksum;
- README commands, paths, version numbers, and download names agree with the generated artifact;
- third-party license and attribution files are included.

Camera behavior receives only a short smoke check against the already validated build. This work does not alter the live/archive transport split, timeline behavior, detection logic, or export implementation.

## GitHub release workflow

1. Prepare documentation, license files, ignore rules, and release metadata in one publication-readiness commit.
2. Build and verify the release candidate locally.
3. Present the final file list, checksum, verification results, README, and release notes for user review.
4. After explicit confirmation, push the commit, change repository visibility to public if needed, create tag `v0.1.0-beta.1`, and publish a GitHub prerelease with the verified assets.

External publication is deliberately separated from local preparation so no source or binary becomes public before final review.

## Out of scope

- Apple Developer signing and notarization;
- DMG creation;
- automatic GitHub Actions releases;
- Mac App Store distribution;
- compatibility claims for untested cameras;
- new application features or playback fixes.
