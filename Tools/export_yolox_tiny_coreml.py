#!/usr/bin/env python3

"""Convert official YOLOX-Tiny 0.1.1rc0 weights to Core ML for MiniCam."""

import argparse
import hashlib
import sys
from pathlib import Path

import coremltools as ct
import torch


EXPECTED_WEIGHTS_SHA256 = (
    "f99294c4cf6df2a384f956371ec31cf4d06fa3a4a859899df0e410a6045904c9"
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--yolox-source", required=True, type=Path)
    parser.add_argument("--weights", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def validate_weights(weights: Path) -> None:
    digest = hashlib.sha256(weights.read_bytes()).hexdigest()
    if digest != EXPECTED_WEIGHTS_SHA256:
        raise ValueError(
            "Expected official YOLOX-Tiny 0.1.1rc0 weights with SHA-256 "
            f"{EXPECTED_WEIGHTS_SHA256}, received {digest}."
        )


def build_model(source: Path, weights: Path) -> torch.nn.Module:
    sys.path.insert(0, str(source))
    from yolox.models import YOLOPAFPN, YOLOX, YOLOXHead

    width = 0.375
    channels = [256, 512, 1024]
    backbone = YOLOPAFPN(
        depth=0.33,
        width=width,
        in_channels=channels,
        act="silu",
        depthwise=False,
    )
    head = YOLOXHead(
        num_classes=80,
        width=width,
        in_channels=channels,
        act="silu",
        depthwise=False,
    )
    model = YOLOX(backbone, head)
    for module in model.modules():
        if isinstance(module, torch.nn.BatchNorm2d):
            module.eps = 1e-3
            module.momentum = 0.03

    checkpoint = torch.load(weights, map_location="cpu")
    model.load_state_dict(checkpoint["model"])
    model.eval()
    model.head.decode_in_inference = True
    return model


def convert(model: torch.nn.Module) -> ct.models.MLModel:
    example = torch.zeros((1, 3, 416, 416), dtype=torch.float32)
    traced = torch.jit.trace(model, example)
    with torch.no_grad():
        output = traced(example)
    if tuple(output.shape) != (1, 3549, 85):
        raise ValueError(f"Unexpected YOLOX output shape: {tuple(output.shape)}")

    converted = ct.convert(
        traced,
        inputs=[
            ct.ImageType(
                name="image",
                shape=example.shape,
                scale=1.0,
                color_layout=ct.colorlayout.BGR,
            )
        ],
        outputs=[ct.TensorType(name="predictions")],
        minimum_deployment_target=ct.target.macOS12,
        compute_precision=ct.precision.FLOAT16,
    )
    converted.author = "Megvii YOLOX, converted for MiniCam"
    converted.license = "Apache License 2.0"
    converted.short_description = "YOLOX-Tiny COCO object detector"
    return converted


def main() -> None:
    arguments = parse_arguments()
    if arguments.output.exists():
        raise FileExistsError(f"Output already exists: {arguments.output}")

    validate_weights(arguments.weights)
    model = build_model(arguments.yolox_source, arguments.weights)
    convert(model).save(arguments.output)
    print(f"Saved {arguments.output}")


if __name__ == "__main__":
    main()
