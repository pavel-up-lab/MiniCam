#!/bin/zsh

set -euo pipefail

VERSION="${1:-0.1.0-beta.2}"
PROJECT_ROOT="${0:A:h:h}"
APP_PATH="${2:-${PROJECT_ROOT}/build-release/Build/Products/Release/MiniCam.app}"
OUTPUT_ROOT="${PROJECT_ROOT}/release"
ARCHIVE_NAME="MiniCam-${VERSION}-macos-universal.zip"
ARCHIVE_PATH="${OUTPUT_ROOT}/${ARCHIVE_NAME}"
CHECKSUM_PATH="${OUTPUT_ROOT}/SHA256SUMS.txt"
STAGING_ROOT="$(mktemp -d /private/tmp/minicam-release.XXXXXX)"
PACKAGE_ROOT="${STAGING_ROOT}/MiniCam-${VERSION}-macos-universal"

cleanup() {
    rm -rf "${STAGING_ROOT}"
}
trap cleanup EXIT

if [[ ! -d "${APP_PATH}" ]]; then
    print -u2 "MiniCam.app was not found at: ${APP_PATH}"
    print -u2 "Build the Release configuration first or pass the app path as argument 2."
    exit 1
fi

if [[ -e "${ARCHIVE_PATH}" || -e "${CHECKSUM_PATH}" ]]; then
    print -u2 "Release output already exists in: ${OUTPUT_ROOT}"
    print -u2 "Move the existing ZIP and checksum before packaging again."
    exit 1
fi

mkdir -p "${PACKAGE_ROOT}/Licenses" "${OUTPUT_ROOT}"
ditto "${APP_PATH}" "${PACKAGE_ROOT}/MiniCam.app"
cp "${PROJECT_ROOT}/LICENSE" "${PACKAGE_ROOT}/LICENSE.txt"
cp "${PROJECT_ROOT}/THIRD_PARTY_NOTICES.md" "${PACKAGE_ROOT}/THIRD_PARTY_NOTICES.md"
cp "${PROJECT_ROOT}"/ThirdPartyLicenses/*.txt "${PACKAGE_ROOT}/Licenses/"

ditto -c -k --sequesterRsrc --keepParent "${PACKAGE_ROOT}" "${ARCHIVE_PATH}"

cd "${OUTPUT_ROOT}"
shasum -a 256 "${ARCHIVE_NAME}" > "${CHECKSUM_PATH}"

print "Created ${ARCHIVE_PATH}"
print "Created ${CHECKSUM_PATH}"
