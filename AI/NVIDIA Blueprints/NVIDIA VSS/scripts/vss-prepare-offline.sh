#!/usr/bin/env bash
# =============================================================================
# vss-prepare-offline.sh
#
# PURPOSE: Run this on an INTERNET-CONNECTED machine.
#          Produces two bundle files needed for the offline VSS deployment:
#
#   1. vss-codecs.tar.gz   — NumPy + OpenCV wheels for vss-agent
#   2. vss-apt-repo.tar.gz — Ubuntu .deb packages for vss-vios-streamprocessing
#
# REQUIREMENTS:
#   - python3 (3.8+) with pip
#   - podman
#   - tar
#
# USAGE:
#   ./vss-prepare-offline.sh
#
# After completion, copy BOTH .tar.gz files to the machine that has
# oc access to your offline OCP cluster, then run vss-deploy-offline.sh.
# =============================================================================

set -euo pipefail

# ── colour helpers ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── banner ────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  VSS Offline — Bundle Preparation (internet machine)"
echo "============================================================"
echo ""
echo -e "${YELLOW}Each prompt shows a default value in [brackets].${NC}"
echo -e "${YELLOW}Press Enter to accept the default, or type a new value.${NC}"
echo ""

# ── prompt helper ─────────────────────────────────────────────────────────────
prompt_if_empty() {
    local var_name="$1" prompt_text="$2" default="$3"
    if [[ -z "${!var_name:-}" ]]; then
        read -rp "${prompt_text} [${default}]: " input
        eval "${var_name}=\"${input:-${default}}\""
    fi
}

# ── inputs ────────────────────────────────────────────────────────────────────
NUMPY_VERSION="${NUMPY_VERSION:-2.4.2}"
OPENCV_VERSION="${OPENCV_VERSION:-4.13.0.92}"
PYTHON_TAG="${PYTHON_TAG:-cp313}"
PLATFORM_TAG="${PLATFORM_TAG:-manylinux_2_28_x86_64}"
CODECS_BUNDLE="${CODECS_BUNDLE:-./vss-codecs.tar.gz}"
APT_BUNDLE="${APT_BUNDLE:-./vss-apt-repo.tar.gz}"

prompt_if_empty NUMPY_VERSION   "NumPy version"                    "$NUMPY_VERSION"
prompt_if_empty OPENCV_VERSION  "opencv-python-headless version"   "$OPENCV_VERSION"
prompt_if_empty CODECS_BUNDLE   "Output path for vss-codecs.tar.gz"    "$CODECS_BUNDLE"
prompt_if_empty APT_BUNDLE      "Output path for vss-apt-repo.tar.gz"  "$APT_BUNDLE"

echo ""
log "NumPy version    : $NUMPY_VERSION"
log "OpenCV version   : $OPENCV_VERSION"
log "Codecs bundle    : $CODECS_BUNDLE"
log "APT bundle       : $APT_BUNDLE"
echo ""

# ── preflight ─────────────────────────────────────────────────────────────────
command -v python3 >/dev/null 2>&1 || die "python3 not found."
PIP_CMD=$(command -v pip3 2>/dev/null || command -v pip 2>/dev/null || true)
[[ -n "$PIP_CMD" ]] || die "pip not found."
command -v podman  >/dev/null 2>&1 || die "podman not found."
command -v tar     >/dev/null 2>&1 || die "tar not found."
ok "Preflight passed (python3, pip, podman, tar)."

# ── working dirs (cleaned up on exit) ────────────────────────────────────────
WORK_DIR="$(mktemp -d)"
WHEELS_DIR="${WORK_DIR}/wheels"
BUNDLE_DIR="${WORK_DIR}/bundle"
PACKAGES_DIR="${WORK_DIR}/packages"
mkdir -p "$WHEELS_DIR" "$BUNDLE_DIR" "$PACKAGES_DIR"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

# ══════════════════════════════════════════════════════════════════════════════
# PART 1 — vss-codecs.tar.gz  (NumPy + OpenCV wheels for vss-agent)
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "------------------------------------------------------------"
echo "  Part 1/2 — Building vss-codecs.tar.gz"
echo "------------------------------------------------------------"

log "Step 1/3 — Downloading wheels from PyPI..."
$PIP_CMD download \
    --only-binary=:all: \
    --python-version "${PYTHON_TAG#cp}" \
    --platform "${PLATFORM_TAG}" \
    --dest "$WHEELS_DIR" \
    "numpy==${NUMPY_VERSION}" \
    "opencv-python-headless==${OPENCV_VERSION}" \
    || die "pip download failed. Check version numbers and network access."

WHEEL_COUNT=$(find "$WHEELS_DIR" -name "*.whl" | wc -l | tr -d ' ')
[[ "$WHEEL_COUNT" -eq 0 ]] && die "No wheels downloaded."
ok "Downloaded ${WHEEL_COUNT} wheel(s)."

log "Step 2/3 — Extracting wheels..."
python3 - <<PY
import zipfile, glob, sys
wheels = glob.glob("${WHEELS_DIR}/*.whl")
if not wheels:
    print("ERROR: no wheels found", file=sys.stderr); sys.exit(1)
for whl in wheels:
    print(f"  Extracting: {whl}")
    with zipfile.ZipFile(whl) as z:
        z.extractall("${BUNDLE_DIR}")
print("  Done.")
PY

[[ -f "${BUNDLE_DIR}/numpy/__init__.py" ]] || die "numpy/__init__.py missing after extraction."
[[ -f "${BUNDLE_DIR}/cv2/__init__.py"   ]] || die "cv2/__init__.py missing after extraction."
ok "Wheels extracted and verified."

log "Step 3/3 — Adding .installed marker and archiving..."
touch "${BUNDLE_DIR}/.installed"
mkdir -p "$(dirname "$CODECS_BUNDLE")"
tar -czf "$CODECS_BUNDLE" -C "$BUNDLE_DIR" .
ok "Created: $CODECS_BUNDLE  ($(du -sh "$CODECS_BUNDLE" | cut -f1))"

# ══════════════════════════════════════════════════════════════════════════════
# PART 2 — vss-apt-repo.tar.gz  (Ubuntu .deb packages for vss-vios-streamprocessing)
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "------------------------------------------------------------"
echo "  Part 2/2 — Building vss-apt-repo.tar.gz"
echo "------------------------------------------------------------"

log "Step 1/2 — Downloading Ubuntu 24.04 .deb packages via podman..."
log "(Pulls ubuntu:24.04 and runs apt-get download — may take a few minutes)"

podman run --rm \
    --arch amd64 \
    -v "${PACKAGES_DIR}:/out:Z" \
    ubuntu:24.04 \
    bash -c '
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends apt-utils ca-certificates -qq
cd /out
apt-get install --download-only --reinstall -y \
  gstreamer1.0-libav \
  gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad \
  gstreamer1.0-plugins-ugly \
  libvo-aacenc0 \
  libfaad2 \
  libswresample-dev \
  libswresample4 \
  libavutil-dev \
  libavcodec-dev \
  libavformat-dev \
  libavfilter-dev \
  libde265-dev \
  libde265-0 \
  libx265-199 \
  libx264-164 \
  libmpeg2encpp-2.1-0 \
  libmpeg2-4 \
  libmpg123-0 \
  libbs2b0 \
  libreadline8 \
  libcdio19 \
  libdca0 \
  libdvdnav4 \
  libmjpegutils-2.1-0 \
  liba52-0.7.4 \
  libdvdread8 \
  libsbc1 \
  libzvbi0 \
  libmp3lame0 \
  libsidplay1v5 \
  liblrdf0 \
  libneon27 \
  libflac12 \
  libxvidcore4 \
  libvpx9 \
  libopenh264-7
cp /var/cache/apt/archives/*.deb /out/ 2>/dev/null || true
echo "Downloaded $(find /out -maxdepth 1 -name "*.deb" | wc -l) packages."
' || die "podman run failed. Check podman setup and network access."

DEB_COUNT=$(find "$PACKAGES_DIR" -maxdepth 1 -name "*.deb" | wc -l | tr -d ' ')
[[ "$DEB_COUNT" -eq 0 ]] && die "No .deb files downloaded."
ok "Downloaded ${DEB_COUNT} .deb package(s)."

log "Step 2/2 — Generating apt Packages index..."
podman run --rm \
    --arch amd64 \
    -v "${PACKAGES_DIR}:/repo:Z" \
    ubuntu:24.04 \
    bash -c '
set -e
apt-get update -qq
apt-get install -y --no-install-recommends dpkg-dev -qq
cd /repo
dpkg-scanpackages --multiversion . > Packages
echo "Packages index: $(wc -l < Packages) lines"
' || die "Failed to generate Packages index."

[[ -f "${PACKAGES_DIR}/Packages" ]] || die "Packages index not found after generation."
ok "Packages index generated."

mkdir -p "$(dirname "$APT_BUNDLE")"
tar -czf "$APT_BUNDLE" -C "$PACKAGES_DIR" .
ok "Created: $APT_BUNDLE  ($(du -sh "$APT_BUNDLE" | cut -f1))"

# ── summary ───────────────────────────────────────────────────────────────────
CODECS_ABS=$(cd "$(dirname "$CODECS_BUNDLE")" && pwd)/$(basename "$CODECS_BUNDLE")
APT_ABS=$(cd "$(dirname "$APT_BUNDLE")" && pwd)/$(basename "$APT_BUNDLE")

echo ""
echo "============================================================"
echo "  Both bundles created successfully:"
echo ""
echo "    $CODECS_ABS"
echo "    $APT_ABS"
echo ""
echo "  Next steps:"
echo "    1. Copy BOTH files to the machine that has oc access"
echo "       to your offline OCP cluster:"
echo ""
echo "       scp $CODECS_ABS user@cluster-machine:~/"
echo "       scp $APT_ABS user@cluster-machine:~/"
echo ""
echo "    2. On the cluster machine, run:"
echo ""
echo "       CODECS_BUNDLE=~/$(basename "$CODECS_BUNDLE") \\"
echo "       APT_BUNDLE=~/$(basename "$APT_BUNDLE") \\"
echo "       ./vss-deploy-offline.sh"
echo ""
echo "    (Or just run ./vss-deploy-offline.sh and enter the"
echo "     paths when prompted.)"
echo "============================================================"
echo ""
