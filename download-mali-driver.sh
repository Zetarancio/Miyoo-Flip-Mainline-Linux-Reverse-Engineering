#!/bin/bash
# Download Mali GPU driver sources: mali_kbase kernel module (ROCKNIX port) + libmali userspace.
# Run from project root. Remove mali-bifrost/ and/or libmali/ to re-download.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Configuration ───
# Mali kernel driver (ROCKNIX bifrost port — already ported to mainline Linux 6.18+)
KBASE_DIR="${KBASE_DIR:-$SCRIPT_DIR/mali-bifrost}"
KBASE_REPO="${KBASE_REPO:-https://github.com/ROCKNIX/mali_kbase.git}"
KBASE_BRANCH="${KBASE_BRANCH:-bifrost_port}"

# libmali userspace (Rockchip blobs from JeffyCN/mirrors, libmali branch)
LIBMALI_DIR="${LIBMALI_DIR:-$SCRIPT_DIR/libmali}"
LIBMALI_REPO="${LIBMALI_REPO:-https://github.com/JeffyCN/mirrors.git}"
LIBMALI_BRANCH="${LIBMALI_BRANCH:-libmali}"

# Target GPU: RK3566 = Bifrost G52, latest DDK = g24p0, platform = GBM (DRM/KMS)
MALI_GPU="bifrost-g52"
MALI_VERSION="g24p0"
MALI_PLATFORM="gbm"
MALI_BLOB="libmali-${MALI_GPU}-${MALI_VERSION}-${MALI_PLATFORM}.so"

# ─── Part 1: Mali kernel driver (mali_kbase) ───
echo "=========================================="
echo "Mali GPU Driver Download"
echo "=========================================="
echo "  GPU:      $MALI_GPU ($MALI_VERSION)"
echo "  Platform: $MALI_PLATFORM"
echo "  Source:   ROCKNIX/mali_kbase (branch: $KBASE_BRANCH)"
echo ""

if [ -d "$KBASE_DIR" ] && [ -d "$KBASE_DIR/product" ]; then
    echo "[kernel] mali-bifrost already present at $KBASE_DIR"
    echo "  To re-clone: rm -rf mali-bifrost && ./download-mali-driver.sh"
else
    echo "[kernel] Cloning Mali Bifrost kernel driver (ROCKNIX port)..."
    rm -rf "$KBASE_DIR"
    git clone --depth 1 -b "$KBASE_BRANCH" "$KBASE_REPO" "$KBASE_DIR"
    echo "[kernel] Ready: $KBASE_DIR"
fi

# ─── Part 2: libmali userspace ───
if [ -d "$LIBMALI_DIR" ] && [ -f "$LIBMALI_DIR/lib/aarch64-linux-gnu/$MALI_BLOB" ]; then
    echo "[userspace] libmali already present at $LIBMALI_DIR"
    echo "  To re-clone: rm -rf libmali && ./download-mali-driver.sh"
else
    echo "[userspace] Cloning libmali (sparse: $MALI_BLOB + headers)..."
    rm -rf "$LIBMALI_DIR"
    # Sparse checkout: only download the blob we need + headers (saves bandwidth)
    git clone --depth 1 -b "$LIBMALI_BRANCH" --single-branch \
        --filter=blob:none --sparse "$LIBMALI_REPO" "$LIBMALI_DIR"
    cd "$LIBMALI_DIR"
    # --skip-checks: allow file paths (sparse-checkout expects dirs by default)
    git sparse-checkout set --skip-checks \
        "lib/aarch64-linux-gnu/$MALI_BLOB" \
        "include/"
    cd "$SCRIPT_DIR"

    # Verify blob was fetched
    if [ ! -f "$LIBMALI_DIR/lib/aarch64-linux-gnu/$MALI_BLOB" ]; then
        echo "Error: Sparse checkout did not fetch $MALI_BLOB"
        echo "Try: rm -rf libmali && ./download-mali-driver.sh"
        exit 1
    fi
    echo "[userspace] Ready: $LIBMALI_DIR"
    echo "  Blob: lib/aarch64-linux-gnu/$MALI_BLOB"
fi

echo ""
echo "=========================================="
echo "Mali GPU driver sources ready"
echo "=========================================="
echo "  Kernel module: $KBASE_DIR/product/kernel/drivers/gpu/arm/midgard/"
echo "  Userspace lib: $LIBMALI_DIR/lib/aarch64-linux-gnu/$MALI_BLOB"
echo ""
echo "Next: make build-mali"
