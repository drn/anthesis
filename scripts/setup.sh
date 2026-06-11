#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Anthesis — Godot+voxel editor setup
#
# Downloads the Zylann godot_voxel v1.6 prebuilt editor and installs it at
# tools/godot/.  Idempotent: skips the download if the binary is already
# present.  Set FORCE=1 to re-download regardless.
# ---------------------------------------------------------------------------

RELEASE_TAG="v1.6"
RELEASE_BASE_URL="https://github.com/Zylann/godot_voxel/releases/download/${RELEASE_TAG}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${REPO_ROOT}/tools/godot"

# ---------- detect platform & arch ----------------------------------------
OS="$(uname -s)"
ARCH="$(uname -m)"

case "${OS}" in
  Darwin)
    # Universal macOS build — no arch-specific asset.
    ASSET="godot.macos.editor.app.zip"
    BINARY="${INSTALL_DIR}/macos_editor.app/Contents/MacOS/Godot"
    ;;
  Linux)
    case "${ARCH}" in
      x86_64) ASSET="godot.linuxbsd.editor.x86_64.zip" ;;
      *)
        echo "ERROR: Unsupported Linux architecture: ${ARCH}"
        echo "Only x86_64 is provided by the Zylann voxel prebuilt release."
        exit 1
        ;;
    esac
    BINARY="${INSTALL_DIR}/godot.linuxbsd.editor.x86_64"
    ;;
  *)
    echo "ERROR: Unsupported OS: ${OS}"
    exit 1
    ;;
esac

DOWNLOAD_URL="${RELEASE_BASE_URL}/${ASSET}"

# ---------- idempotency check ----------------------------------------------
if [ -f "${BINARY}" ] && [ "${FORCE:-0}" != "1" ]; then
  echo "Godot binary already present at: ${BINARY}"
  echo "(Set FORCE=1 to re-download.)"
else
  echo "Downloading ${ASSET} from ${DOWNLOAD_URL} ..."
  mkdir -p "${INSTALL_DIR}"

  TMPDIR="$(mktemp -d)"
  trap 'rm -rf "${TMPDIR}"' EXIT

  OUTER_ZIP="${TMPDIR}/${ASSET}"
  curl -fL --progress-bar "${DOWNLOAD_URL}" -o "${OUTER_ZIP}"

  echo "Extracting ..."

  case "${OS}" in
    Darwin)
      # The release ships a nested zip:
      #   godot.macos.editor.app.zip
      #     └─ macos_editor.app.zip   (inner zip)
      #          └─ macos_editor.app/  (the .app bundle)
      unzip -q "${OUTER_ZIP}" -d "${TMPDIR}/outer"

      # Find the inner zip (may be named macos_editor.app.zip or similar).
      INNER_ZIP="$(find "${TMPDIR}/outer" -maxdepth 2 -name "*.zip" | head -1)"

      if [ -n "${INNER_ZIP}" ]; then
        echo "Found inner zip: $(basename "${INNER_ZIP}") — extracting into ${INSTALL_DIR}/ ..."
        unzip -q "${INNER_ZIP}" -d "${INSTALL_DIR}"
      else
        # Fallback: no inner zip — move whatever landed in outer/ into install dir.
        echo "No inner zip found; moving extracted contents to ${INSTALL_DIR}/ ..."
        cp -R "${TMPDIR}/outer/." "${INSTALL_DIR}/"
      fi

      # Remove macOS quarantine attribute so the app can run without Gatekeeper prompts.
      if [ -d "${INSTALL_DIR}/macos_editor.app" ]; then
        xattr -r -d com.apple.quarantine "${INSTALL_DIR}/macos_editor.app" 2>/dev/null || true
      fi
      ;;

    Linux)
      unzip -q "${OUTER_ZIP}" -d "${TMPDIR}/outer"
      # The Linux asset extracts the binary directly.
      EXTRACTED="$(find "${TMPDIR}/outer" -maxdepth 2 -type f | head -1)"
      if [ -z "${EXTRACTED}" ]; then
        echo "ERROR: Nothing extracted from ${ASSET}"
        exit 1
      fi
      DEST="${INSTALL_DIR}/$(basename "${EXTRACTED}")"
      cp "${EXTRACTED}" "${DEST}"
      chmod +x "${DEST}"
      ;;
  esac

  echo "Installation complete."
fi

# ---------- verify ---------------------------------------------------------
echo ""
echo "Godot binary: ${BINARY}"
"${BINARY}" --version

# ---------- gdtoolkit hint -------------------------------------------------
echo ""
if ! command -v gdlint &>/dev/null; then
  echo "HINT: gdtoolkit (gdlint / gdformat) is not installed."
  echo "      Install it with:"
  echo "        pip install 'gdtoolkit==4.*'"
fi
