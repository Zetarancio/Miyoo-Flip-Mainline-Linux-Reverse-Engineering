#!/bin/bash
# Clone RTL8733BU WiFi driver and apply kernel 6.19 compatibility patch.
# Run from project root. If RTL8733BU/ already exists, remove it first to re-clone.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER_DIR="${DRIVER_DIR:-$SCRIPT_DIR/RTL8733BU}"
DRIVER_REPO="${DRIVER_REPO:-https://github.com/ROCKNIX/RTL8733BU.git}"
DRIVER_BRANCH="${DRIVER_BRANCH:-v5.15.12-126-wb}"

if [ -d "$DRIVER_DIR" ] && [ -f "$DRIVER_DIR/Makefile" ]; then
    echo "RTL8733BU driver source already present at $DRIVER_DIR"
    echo "To re-clone: rm -rf RTL8733BU && ./download-wifi-driver.sh"
    exit 1
fi

echo "Cloning RTL8733BU WiFi driver (branch: $DRIVER_BRANCH)..."
git clone --depth 1 -b "$DRIVER_BRANCH" "$DRIVER_REPO" "$DRIVER_DIR"

# Apply kernel 6.19 compatibility patch if available
PATCH_DIR="$SCRIPT_DIR/patches"
DRIVER_PATCH="$PATCH_DIR/0002-rtl8733bu-linux-6.19-compat.patch"
if [ -f "$DRIVER_PATCH" ]; then
    echo "Applying WiFi driver patches..."
    cd "$DRIVER_DIR"
    if git apply --check "$DRIVER_PATCH" 2>/dev/null; then
        git apply "$DRIVER_PATCH"
        echo "  Applied: $(basename "$DRIVER_PATCH")"
    else
        echo "  Warning: Patch $(basename "$DRIVER_PATCH") does not apply cleanly. Apply manually."
    fi
    cd "$SCRIPT_DIR"
fi

echo "RTL8733BU driver source ready at: $DRIVER_DIR"
echo "Next: make build-wifi"
