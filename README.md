# MiniCam

[Русская версия](README.ru.md)

MiniCam is a native macOS viewer for a single Hikvision-compatible IP camera. It combines a low-latency live view with a continuous timeline of recordings stored on the camera's microSD card.

> **Beta software:** MiniCam has been tested with a limited set of hardware. Camera firmware and ISAPI implementations vary, so archive playback may not work with every model.

## Features

- Low-latency RTSP live view.
- One timeline for live and microSD archive playback.
- Calendar navigation and precise archive seeking.
- Play, pause, and 10/30-second step controls.
- Local motion-event detection for people and vehicles.
- Event cards with a thumbnail and click-to-seek navigation.
- PNG snapshots of the displayed live or archive frame.
- MP4 export of a continuous archive interval up to 30 minutes.
- Configurable local or external storage for cached frames.
- Adjustable player interface text at `1×`, `1.5×`, or `2×` scale.
- No camera cloud account, separate recording server, telemetry, or subscription.

All camera credentials remain on the Mac. The password is stored in macOS Keychain.

## Requirements

- macOS Monterey 12 or later.
- Intel (`x86_64`) or Apple Silicon (`arm64`) Mac.
- A camera reachable on the same local network.
- A Hikvision-compatible ISAPI archive with continuous recording enabled on the camera's microSD card.
- H.264 is recommended, especially on older Intel Macs.

Tested hardware: **Hikvision DS-2CD2043G2-IU**, channel 1, continuous microSD recording. Other Hikvision and compatible models may work but are not yet verified.

## Download and install

1. Open the [`v0.1.0-beta.2` release](https://github.com/pavel-up-lab/MiniCam/releases/tag/v0.1.0-beta.2).
2. Download `MiniCam-0.1.0-beta.2-macos-universal.zip` and optionally verify it with `SHA256SUMS.txt`.
3. Unzip the download and move `MiniCam.app` to the Applications folder.
4. Open MiniCam.

The beta is ad-hoc signed but is **not notarized**, because the project does not currently have an Apple Developer ID certificate. If macOS blocks the first launch:

1. Try to open MiniCam once.
2. Open **System Settings → Privacy & Security**.
3. Find the message about MiniCam and choose **Open Anyway**.
4. Confirm by choosing **Open**.

Do not disable Gatekeeper globally.

## Camera setup

Before connecting MiniCam:

1. Enable continuous 24/7 recording on the camera's microSD card.
2. Synchronize the camera time and time zone.
3. Enable RTSP and ISAPI access if the firmware exposes these switches.
4. Close unnecessary camera browser previews, VLC windows, and other MiniCam copies.

At first launch, enter the camera address without a protocol, for example `192.0.2.10`, together with its HTTP and RTSP ports, username, and password. Typical ports are HTTP `80` and RTSP `554`; use the actual values configured on your camera.

MiniCam uses Hikvision ISAPI to discover recordings and RTSP to play live and archive video. It does not record a second continuous copy of the stream on the Mac.

## Motion events

MiniCam analyzes only newly added archive intervals while the application is running. It can record the start of motion for people only or for people and vehicles. Static objects do not create events, and detection boxes are not drawn over the video.

Detection runs locally using a bundled YOLOX-Tiny Core ML model. Historical recordings from before the application was started are not scanned retroactively.

## Privacy

- No telemetry or analytics.
- No MiniCam cloud service.
- No camera credentials in logs or stored RTSP URLs.
- Passwords are stored in macOS Keychain.
- Timeline frames, event thumbnails, and screenshots stay in folders selected by the user.
- Video and images are not uploaded by MiniCam.

## Known limitations

- Only one camera is supported.
- Remote access and relay services are not included.
- Archive playback depends on Hikvision ISAPI behavior and camera firmware.
- Opening an arbitrary archive position may take 1–3 seconds.
- The camera may permit only two simultaneous RTSP sessions. Extra viewers can cause `453 Not Enough Bandwidth`, a black picture, or a failed export.
- Archive export is usually close to real time because many cameras deliver playback at recording speed.
- Motion detection processes only new archive data received while MiniCam is running.
- The build is not notarized and must be approved manually on first launch.

## Troubleshooting

### Live or archive video is black

Close VLC, browser camera previews, and other MiniCam copies, wait a few seconds, and reconnect. Confirm that the camera has continuous recordings for the selected time.

### `453 Not Enough Bandwidth`

The camera has run out of RTSP sessions or decoder resources. Disconnect other clients before retrying.

### Archive time is incorrect

Set the correct time zone and NTP synchronization on the camera, then reconnect MiniCam.

### No motion events appear

Keep MiniCam running while new archive intervals are created. Check that motion tracking is enabled and that the event filter includes the required object type.

When reporting a problem, include the Mac model and architecture, macOS version, camera model and firmware, video codec, and whether the issue affects live view, archive playback, or both. Never post a camera password or an authenticated RTSP URL.

## Build from source

Requirements:

- Xcode 14 or later.
- CocoaPods.

```bash
git clone https://github.com/pavel-up-lab/MiniCam.git
cd MiniCam
pod install
open MiniCam.xcworkspace
```

Build the shared `MiniCam` scheme from the workspace, not directly from the Xcode project. The Core ML model and universal minimal FFmpeg executable used by the beta are tracked in the repository. Their reproducible conversion/build tools are available in [`Tools`](Tools/).

## License

MiniCam source code is available under the [MIT License](LICENSE). Bundled components retain their own licenses; see [third-party notices](THIRD_PARTY_NOTICES.md) and [`ThirdPartyLicenses`](ThirdPartyLicenses/).

MiniCam is an independent project and is not affiliated with or endorsed by Hikvision or Apple.
