#!/bin/zsh

set -euo pipefail

FFMPEG_VERSION="8.1.2"
FFMPEG_ARCHIVE="/private/tmp/ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_SOURCE_ROOT="/private/tmp/minicam-ffmpeg-${FFMPEG_VERSION}"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
PROJECT_ROOT="${0:A:h:h}"
OUTPUT="${PROJECT_ROOT}/MiniCam/Resources/ffmpeg"
SDK_ROOT="$(xcrun --sdk macosx --show-sdk-path)"
CLANG="$(xcrun --find clang)"

if [[ ! -f "${FFMPEG_ARCHIVE}" ]]; then
    curl --fail --location --retry 3 "${FFMPEG_URL}" --output "${FFMPEG_ARCHIVE}"
fi

rm -rf "${FFMPEG_SOURCE_ROOT}"
mkdir -p "${FFMPEG_SOURCE_ROOT}"
tar -xf "${FFMPEG_ARCHIVE}" -C "${FFMPEG_SOURCE_ROOT}" --strip-components=1

for TARGET_ARCH in arm64 x86_64; do
    THIN_OUTPUT="/private/tmp/minicam-ffmpeg-${TARGET_ARCH}"
    if [[ "${MINICAM_FFMPEG_REBUILD:-0}" != "1" ]] \
        && [[ -x "${THIN_OUTPUT}" ]] \
        && file "${THIN_OUTPUT}" | grep -q "${TARGET_ARCH}"; then
        continue
    fi
    BUILD_ROOT="/private/tmp/minicam-ffmpeg-build-${TARGET_ARCH}"
    rm -rf "${BUILD_ROOT}"
    mkdir -p "${BUILD_ROOT}"
    cd "${BUILD_ROOT}"

    "${FFMPEG_SOURCE_ROOT}/configure" \
        --prefix="${BUILD_ROOT}/install" \
        --target-os=darwin \
        --arch="${TARGET_ARCH}" \
        --cc="${CLANG}" \
        --sysroot="${SDK_ROOT}" \
        --enable-cross-compile \
        --disable-everything \
        --disable-autodetect \
        --disable-doc \
        --disable-debug \
        --disable-iconv \
        --disable-securetransport \
        --disable-videotoolbox \
        --disable-audiotoolbox \
        --disable-x86asm \
        --enable-ffmpeg \
        --enable-network \
        --enable-protocol=file,pipe,tcp,udp,rtp \
        --enable-demuxer=rtsp,rtp,sdp,mov,concat \
        --enable-muxer=mov,mp4 \
        --enable-parser=h264,hevc \
        --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb \
        --extra-cflags="-arch ${TARGET_ARCH} -mmacosx-version-min=12.0" \
        --extra-ldflags="-arch ${TARGET_ARCH} -mmacosx-version-min=12.0"

    make -j8 ffmpeg
    cp ffmpeg "${THIN_OUTPUT}"
done

lipo -create \
    /private/tmp/minicam-ffmpeg-arm64 \
    /private/tmp/minicam-ffmpeg-x86_64 \
    -output "${OUTPUT}"
chmod 755 "${OUTPUT}"

cp "${FFMPEG_SOURCE_ROOT}/COPYING.LGPLv2.1" \
    "${PROJECT_ROOT}/ThirdPartyLicenses/FFmpeg-LGPL-2.1.txt"

file "${OUTPUT}"
otool -L "${OUTPUT}"
"${OUTPUT}" -version | head -3
