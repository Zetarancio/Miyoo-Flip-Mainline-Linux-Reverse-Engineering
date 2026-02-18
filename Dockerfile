# Dockerfile for building Miyoo Flip OS
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install build dependencies and cross-toolchain for U-Boot (make.sh expects aarch64-linux-gnu-)
RUN apt-get update && apt-get install -y \
    build-essential \
    gcc-aarch64-linux-gnu \
    git \
    wget \
    curl \
    bison \
    flex \
    libssl-dev \
    libncurses-dev \
    bc \
    device-tree-compiler \
    python3 \
    python3-pip \
    python3-dev \
    swig \
    qemu-user-static \
    binfmt-support \
    parted \
    kpartx \
    dosfstools \
    e2fsprogs \
    file \
    gdisk \
    rsync \
    cpio \
    xz-utils \
    zip \
    unzip \
    p7zip-full \
    cmake \
    pkg-config \
    libusb-1.0-0-dev \
    ccache \
    lz4 \
    squashfs-tools \
    && rm -rf /var/lib/apt/lists/*

# Install dt-schema for DTS validation
RUN pip3 install dtschema

# mkbootimg: use Extra/miyoo-flip-main/u-boot/scripts/mkbootimg (bind-mounted at runtime). See build-boot-img.sh.

# Set working directory
WORKDIR /build

# Create build directories
RUN mkdir -p /build/{output,rootfs,kernel,uboot,dts,buildroot}

# Setup ccache
RUN mkdir -p /build/.ccache && \
    ccache --set-config=cache_dir=/build/.ccache && \
    ccache --set-config=max_size=10G

# Copy only build scripts and static device tree
COPY build-*.sh /build/
COPY rebuild-dtb-for-uboot.sh /build/
COPY docker-entrypoint.sh /build/
COPY build-rootfs-buildroot.sh /build/
COPY build-rtl8733bu.sh /build/
COPY rk3566-miyoo-flip.dts /build/
COPY dbus-users.table /build/

RUN chmod +x /build/*.sh

# Note: Large source directories (Extra/, toolchains) will be bind-mounted at runtime
# This avoids copying 10GB+ into Docker build context

ENTRYPOINT ["/build/docker-entrypoint.sh"]
CMD []
