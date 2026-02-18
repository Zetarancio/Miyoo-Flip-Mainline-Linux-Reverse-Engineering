#!/bin/bash
# Docker entrypoint script
set -e

# Check that required directories are bind-mounted
if [ ! -d "/build/Extra" ]; then
    echo "Error: Extra/ directory not found. Please bind-mount it:"
    echo "  docker run -v \$(pwd)/Extra:/build/Extra:ro ..."
    exit 1
fi

# Look for SDK Buildroot toolchain (preferred). Require that nm works (kernel check-local-export uses it).
if [ -d "/build/Extra/miyoo355_sdk_release/host/bin" ]; then
    TOOLCHAIN_BIN="/build/Extra/miyoo355_sdk_release/host/bin"
    GCC="$TOOLCHAIN_BIN/aarch64-buildroot-linux-gnu-gcc"
    NM="$TOOLCHAIN_BIN/aarch64-buildroot-linux-gnu-nm"
    if [ -f "$GCC" ] && [ -x "$NM" ]; then
        if "$NM" --version >/dev/null 2>&1; then
            export PATH="$TOOLCHAIN_BIN:$PATH"
            export CROSS_COMPILE="aarch64-buildroot-linux-gnu-"
            echo "Using SDK Buildroot toolchain: aarch64-buildroot-linux-gnu-"
        fi
    fi
fi

# Fallback: Look for other toolchains in Extra. Only use one whose nm runs (kernel build needs it).
if [ -z "$CROSS_COMPILE" ]; then
    for search in "/build/Extra/flip" /build/Extra/gcc-arm-* /build/Extra/*toolchain*; do
        [ -d "$search" ] || continue
        GCC=$(find "$search" -name "*aarch64*gcc" -type f 2>/dev/null | head -1)
        [ -n "$GCC" ] || continue
        TOOLCHAIN_BIN=$(dirname "$GCC")
        CROSS_PREFIX=$(basename "$GCC" | sed 's/-gcc$//')-
        NM="$TOOLCHAIN_BIN/${CROSS_PREFIX}nm"
        if [ -x "$NM" ] && "$NM" --version >/dev/null 2>&1; then
            export PATH="$TOOLCHAIN_BIN:$PATH"
            export CROSS_COMPILE="$CROSS_PREFIX"
            echo "Using toolchain: $CROSS_PREFIX"
            break
        fi
    done
fi

# Default to aarch64 toolchain if available in PATH
if [ -z "$CROSS_COMPILE" ]; then
    if command -v aarch64-none-linux-gnu-gcc >/dev/null 2>&1; then
        export CROSS_COMPILE="aarch64-none-linux-gnu-"
    elif command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
        export CROSS_COMPILE="aarch64-linux-gnu-"
    else
        echo "Warning: No cross-compiler found. Install one or bind-mount toolchain."
    fi
fi

export ARCH=arm64

# Execute command
if [ $# -eq 0 ]; then
    # No arguments, run build-all
    exec /build/build-all.sh
elif [ "$1" = "build-all" ]; then
    # "build-all" as argument, run the script
    exec /build/build-all.sh
elif [ -f "/build/$1" ]; then
    # Script in /build (bind-mounted files may not appear executable in container)
    case "$1" in *.sh) exec /bin/bash "/build/$1" ;; *) exec "/build/$1" ;; esac
else
    # Pass through other commands
    exec "$@"
fi
