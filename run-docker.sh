#!/bin/bash
# Run the builder container with the same bind mounts as the Makefile.
# Usage:
#   ./run-docker.sh              # interactive shell
#   ./run-docker.sh ./build-uboot.sh
#   ./run-docker.sh bash -c "./build-uboot.sh && ./build-boot-img.sh"
set -e
cd "$(dirname "$0")"
mkdir -p output .ccache kernel buildroot .cursor
if [ ! -d "Extra" ]; then
    echo "Error: Extra/ directory not found."
    exit 1
fi
CURDIR_ABS="$(pwd)"
if [ $# -eq 0 ]; then
    echo "Starting interactive shell (workdir: /build). Example: ./build-uboot.sh"
    exec docker run -it --rm \
        -v "$CURDIR_ABS/output:/build/output" \
        -v "$CURDIR_ABS/Extra:/build/Extra:ro" \
        -v "$CURDIR_ABS/.ccache:/build/.ccache" \
        -v "$CURDIR_ABS/kernel:/build/kernel" \
        -v "$CURDIR_ABS/buildroot:/build/buildroot" \
        -v "$CURDIR_ABS/.cursor:/build/.cursor" \
        miyoo-flip-builder \
        bash
else
    exec docker run --rm \
        -v "$CURDIR_ABS/output:/build/output" \
        -v "$CURDIR_ABS/Extra:/build/Extra:ro" \
        -v "$CURDIR_ABS/.ccache:/build/.ccache" \
        -v "$CURDIR_ABS/kernel:/build/kernel" \
        -v "$CURDIR_ABS/buildroot:/build/buildroot" \
        -v "$CURDIR_ABS/.cursor:/build/.cursor" \
        miyoo-flip-builder \
        "$@"
fi
