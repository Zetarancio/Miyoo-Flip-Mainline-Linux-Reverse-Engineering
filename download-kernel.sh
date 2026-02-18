#!/bin/bash
# Download mainline Linux kernel into kernel/ for building.
# Run from project root. If kernel/ already exists, remove it first to re-download.
#
# KERNEL_BRANCH options:
#   linux-6.6.y     - LTS (default)
#   linux-6.1.y     - Older LTS, known to boot on Miyoo Flip
#   latest          - Latest stable branch (e.g. linux-6.19.y); try for newest fixes
#   linux-6.12.y    - Another LTS
# Example: KERNEL_BRANCH=latest ./download-kernel.sh
# Then: make clean-kernel && make build-kernel && make boot-img
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${KERNEL_DIR:-$SCRIPT_DIR/kernel}"
KERNEL_BRANCH="${KERNEL_BRANCH:-linux-6.6.y}"
KERNEL_REPO="${KERNEL_REPO:-https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git}"

# Resolve "latest" to the newest linux-X.y branch from the stable repo
if [ "$KERNEL_BRANCH" = "latest" ]; then
    echo "Resolving latest stable kernel branch..."
    KERNEL_BRANCH=$(git ls-remote --refs "$KERNEL_REPO" 'refs/heads/linux-*' 2>/dev/null | sed 's|.*refs/heads/||' | grep -E '^linux-[0-9]+\.[0-9]+\.y$' | sort -V | tail -1)
    if [ -z "$KERNEL_BRANCH" ]; then
        echo "Error: Could not discover latest branch. Try: KERNEL_BRANCH=linux-6.12.y ./download-kernel.sh" >&2
        exit 1
    fi
    echo "Using branch: $KERNEL_BRANCH"
fi

if [ -d "$KERNEL_DIR" ] && [ -f "$KERNEL_DIR/Makefile" ]; then
    echo "Kernel source already present at $KERNEL_DIR"
    echo "To start over and re-download: remove the directory first, then run this script again."
    echo "  Example: rm -rf kernel && ./download-kernel.sh"
    exit 1
fi

if [ -d "$KERNEL_DIR" ] && [ -d "$KERNEL_DIR/.git" ]; then
    echo "Partial or existing git tree at $KERNEL_DIR. Remove it to re-download."
    echo "  Example: rm -rf kernel && ./download-kernel.sh"
    exit 1
fi

echo "Downloading mainline Linux kernel (branch: $KERNEL_BRANCH)..."
mkdir -p "$(dirname "$KERNEL_DIR")"

# Large postBuffer and retries help with "early EOF" / flaky connections to kernel.org
export GIT_HTTP_LOW_SPEED_LIMIT=1000
export GIT_HTTP_LOW_SPEED_TIME=60
git config --global http.postBuffer 524288000 2>/dev/null || true

clone_attempt=1
max_attempts=3
while [ "$clone_attempt" -le "$max_attempts" ]; do
    if git clone --depth 1 --branch "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_DIR"; then
        break
    fi
    if [ "$clone_attempt" -eq "$max_attempts" ]; then
        echo ""
        echo "Clone failed after $max_attempts attempts."
        echo "  - Retry later: rm -rf kernel && ./download-kernel.sh"
        echo "  - Or try another branch: KERNEL_BRANCH=linux-6.1.y ./download-kernel.sh"
        echo "  - Or tarball: wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.<ver>.tar.xz && tar -xf linux-6.6.*.tar.xz && mv linux-6.6.* kernel"
        exit 1
    fi
    echo "Retrying in 10s (attempt $((clone_attempt + 1))/$max_attempts)..."
    rm -rf "$KERNEL_DIR"
    sleep 10
    clone_attempt=$((clone_attempt + 1))
done

# Apply kernel patches if available (in numeric order: 0001, 0008, ...)
PATCH_DIR="$SCRIPT_DIR/patches"
APPLIED=0
for PATCH in "$PATCH_DIR"/*.patch; do
    [ -f "$PATCH" ] || continue
    [ "$APPLIED" -eq 0 ] && echo "Applying kernel patches..." && APPLIED=1
    cd "$KERNEL_DIR"
    if git apply --check "$PATCH" 2>/dev/null; then
        git apply "$PATCH"
        echo "  Applied: $(basename "$PATCH")"
    else
        echo "  Warning: Patch $(basename "$PATCH") does not apply cleanly (kernel version mismatch?). Apply manually."
    fi
    cd "$SCRIPT_DIR"
done

echo "Kernel source ready at: $KERNEL_DIR"
echo "Next: make build-kernel && make boot-img"
