# Third-party notices

## YOLOX-Nano

MiniCam bundles a Core ML conversion of the YOLOX-Nano 0.1.1rc0 model from
Megvii BaseDetection. YOLOX source code and model weights are distributed under
the Apache License 2.0.

- Source: https://github.com/Megvii-BaseDetection/YOLOX
- Official weights: https://github.com/Megvii-BaseDetection/YOLOX/releases/download/0.1.1rc0/yolox_nano.pth
- Weights SHA-256: `cd28f55fbbc1829f99d9ac9b38a16d259a22889739c8728ea877610201feff7b`
- License copy: `ThirdPartyLicenses/YOLOX-LICENSE.txt`

The bundled model is converted with `Tools/export_yolox_nano_coreml.py` for a
416×416 BGR input and a macOS 12 Core ML ML Program deployment target.
