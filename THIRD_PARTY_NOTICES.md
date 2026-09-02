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
