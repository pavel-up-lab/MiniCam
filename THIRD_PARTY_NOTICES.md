# Third-party notices

## YOLOX-Tiny

MiniCam bundles a Core ML conversion of the YOLOX-Tiny 0.1.1rc0 model from
Megvii BaseDetection. YOLOX source code and model weights are distributed under
the Apache License 2.0.

- Source: https://github.com/Megvii-BaseDetection/YOLOX
- Official weights: https://github.com/Megvii-BaseDetection/YOLOX/releases/download/0.1.1rc0/yolox_tiny.pth
- Weights SHA-256: `f99294c4cf6df2a384f956371ec31cf4d06fa3a4a859899df0e410a6045904c9`
- License copy: `ThirdPartyLicenses/YOLOX-LICENSE.txt`

The bundled model is converted with `Tools/export_yolox_tiny_coreml.py` for a
416×416 BGR input and a macOS 12 Core ML ML Program deployment target.

## FFmpeg

MiniCam includes an unmodified, minimal command-line build of FFmpeg 8.1.2
under the GNU Lesser General Public License version 2.1 or later. It is used
only to copy Hikvision archive streams into MP4 files and join adjacent parts;
GPL and non-free components are disabled.

- Project: https://ffmpeg.org/
- Corresponding source: https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz
- Source SHA-256: `464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c`
- Universal executable SHA-256: `5734a833fdf1f74f5ccd27f62de0636aed318f40b02da42e74c8e757faf91f12`
- License copy: `ThirdPartyLicenses/FFmpeg-LGPL-2.1.txt`
- Reproducible build command: `Tools/build_minimal_ffmpeg.sh`

The bundled executable contains `x86_64` and `arm64` slices with a minimum
macOS 12 deployment target. MiniCam starts FFmpeg as a separate executable and
does not link its application binary with FFmpeg libraries.
