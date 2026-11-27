#!/usr/bin/env bash
# Downloads and verifies the prebuilt aspen binary matching the runner.
# Writes `bin=<path>` to $GITHUB_OUTPUT.
set -euo pipefail

REPO="${ACTION_REPOSITORY:-DigitalPebble/aspen}"
VERSION="${INPUT_VERSION:-}"

# Pinned to a release tag (uses: DigitalPebble/aspen@v0.3.0) or to the floating
# major tag (uses: DigitalPebble/aspen@v1) => matching binary.
if [ -z "$VERSION" ] && [[ "${ACTION_REF:-}" =~ ^v?[0-9]+(\.[0-9]+\.[0-9]+)?$ ]]; then
  VERSION="$ACTION_REF"
fi

if [ -z "$VERSION" ]; then
  echo "::error::Cannot derive a release from the ref '${ACTION_REF:-local}': pass version: vX.Y.Z when pinning to a SHA or branch"
  exit 1
fi

# `latest` resolves to the newest release, `v1` to the newest v1.x.y release.
if [ "$VERSION" = "latest" ] || [[ "$VERSION" =~ ^v?[0-9]+$ ]]; then
  auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  if [ "$VERSION" = "latest" ]; then
    PATTERN='[^"]*'
  else
    PATTERN="v\\?${VERSION#v}\\.[0-9]*\\.[0-9]*"
  fi
  # Releases are listed newest first.
  RESOLVED=$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/$REPO/releases?per_page=100" \
    | sed -n "s/.*\"tag_name\": *\"\($PATTERN\)\".*/\1/p" | head -n 1)
  [ -n "$RESOLVED" ] || { echo "::error::Could not find a release of $REPO matching '$VERSION'"; exit 1; }
  echo "Resolved '$VERSION' to $RESOLVED"
  VERSION="$RESOLVED"
fi

case "${RUNNER_OS:-}-${RUNNER_ARCH:-}" in
  Linux-X64)    TARGET=x86_64-unknown-linux-gnu;  EXT=tar.gz; EXE=aspen ;;
  Linux-ARM64)  TARGET=aarch64-unknown-linux-gnu; EXT=tar.gz; EXE=aspen ;;
  macOS-ARM64)  TARGET=aarch64-apple-darwin;      EXT=tar.gz; EXE=aspen ;;
  Windows-X64)  TARGET=x86_64-pc-windows-msvc;    EXT=zip;    EXE=aspen.exe ;;
  *)
    echo "::error::No prebuilt binary for ${RUNNER_OS:-?}/${RUNNER_ARCH:-?}"
    exit 1
    ;;
esac

ASSET="aspen-$VERSION-$TARGET.$EXT"
URL="https://github.com/$REPO/releases/download/$VERSION"
DEST="${RUNNER_TEMP:-/tmp}/aspen-$VERSION"
mkdir -p "$DEST"

echo "Downloading $ASSET"
curl -fsSL --retry 3 -o "$DEST/$ASSET" "$URL/$ASSET" \
  || { echo "::error::Could not download $URL/$ASSET"; exit 1; }
curl -fsSL --retry 3 -o "$DEST/$ASSET.sha256" "$URL/aspen-$VERSION-$TARGET.sha256" \
  || { echo "::error::Could not download the checksum for $ASSET"; exit 1; }

EXPECTED=$(cut -d' ' -f1 "$DEST/$ASSET.sha256")
if command -v sha256sum >/dev/null; then
  ACTUAL=$(sha256sum "$DEST/$ASSET" | cut -d' ' -f1)
else
  ACTUAL=$(shasum -a 256 "$DEST/$ASSET" | cut -d' ' -f1)
fi
if [ -z "$EXPECTED" ] || [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "::error::Checksum mismatch for $ASSET (expected '$EXPECTED', got '$ACTUAL')"
  exit 1
fi
echo "Checksum OK ($ACTUAL)"

# The checksum only catches corruption. The attestation proves the archive was
# built by this repository's release workflow.
command -v gh >/dev/null \
  || { echo "::error::The GitHub CLI (gh) is required to verify the build attestation"; exit 1; }
gh attestation verify "$DEST/$ASSET" --repo "$REPO" >/dev/null \
  || { echo "::error::Attestation verification failed for $ASSET"; exit 1; }
echo "Attestation OK"

if [ "$EXT" = "zip" ]; then
  unzip -q -o "$DEST/$ASSET" -d "$DEST" 2>/dev/null || 7z x -y -o"$DEST" "$DEST/$ASSET" >/dev/null
else
  tar -xzf "$DEST/$ASSET" -C "$DEST"
fi
chmod +x "$DEST/$EXE"

echo "bin=$DEST/$EXE" >> "${GITHUB_OUTPUT:-/dev/stdout}"
