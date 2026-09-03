# Changelog

All notable public changes to MiniCam are documented here.

## [0.1.0-beta.1] - 2026-09-03

First public beta.

### Added

- Low-latency live playback for one Hikvision-compatible camera.
- Continuous live/archive timeline backed by the camera's microSD recordings.
- Calendar navigation, scrubbing previews, play/pause, and 10/30-second steps.
- Local people and vehicle motion events with thumbnails and click-to-seek.
- Configurable event retention and local/external frame storage.
- PNG snapshots and continuous MP4 archive export up to 30 minutes.
- Universal support for Intel and Apple Silicon Macs running macOS 12 or later.

### Known limitations

- Compatibility has primarily been tested with Hikvision DS-2CD2043G2-IU.
- The application supports one camera and local-network access only.
- The build is not notarized and requires manual approval on first launch.
- Camera RTSP session limits can prevent playback or export while other clients are connected.
- Archive export may run close to real time.
- Motion analysis does not scan older recordings retroactively.
