# Makefile for Miyoo Flip Build System
.PHONY: all build build-kernel build-rootfs build-uboot build-wifi build-mali build-dmc boot-img rootfs-img docker-build docker-image docker-run shell clean clean-kernel clean-rootfs download-kernel download-wifi download-mali help

# Get absolute path to current directory (where make is run from)
CURDIR_ABS := $(shell pwd)
# Bind-mount host DTS so kernel build always uses current rk3566-miyoo-flip.dts (avoids needing clean-kernel or docker-build after DTS edits).
# Must run make from the directory that contains rk3566-miyoo-flip.dts (project root) or DTS_VOL is empty and the image's stale DTS is used.
DTS_FILE := $(CURDIR_ABS)/rk3566-miyoo-flip.dts
DTS_VOL := $(if $(wildcard $(DTS_FILE)),-v $(DTS_FILE):/build/rk3566-miyoo-flip.dts:ro,)
# Bind-mount host build-kernel.sh so script edits apply without rebuilding the image
BUILD_KERNEL_SH := $(CURDIR_ABS)/build-kernel.sh
BUILD_KERNEL_VOL := $(if $(wildcard $(BUILD_KERNEL_SH)),-v $(BUILD_KERNEL_SH):/build/build-kernel.sh:ro,)
# Bind-mount host build-rootfs-buildroot.sh so script edits apply without rebuilding the image
BUILD_ROOTFS_SH := $(CURDIR_ABS)/build-rootfs-buildroot.sh
BUILD_ROOTFS_VOL := $(if $(wildcard $(BUILD_ROOTFS_SH)),-v $(BUILD_ROOTFS_SH):/build/build-rootfs-buildroot.sh:ro,)
# Bind-mount host build-rtl8733bu.sh so WiFi driver build script edits apply without rebuilding the image
BUILD_WIFI_SH := $(CURDIR_ABS)/build-rtl8733bu.sh
BUILD_WIFI_VOL := $(if $(wildcard $(BUILD_WIFI_SH)),-v $(BUILD_WIFI_SH):/build/build-rtl8733bu.sh:ro,)
# Bind-mount host build-mali-kbase.sh so Mali GPU driver build script edits apply without rebuilding the image
BUILD_MALI_SH := $(CURDIR_ABS)/build-mali-kbase.sh
BUILD_MALI_VOL := $(if $(wildcard $(BUILD_MALI_SH)),-v $(BUILD_MALI_SH):/build/build-mali-kbase.sh:ro,)
# Bind-mount host build-rootfs-img.sh so rootfs packing script is available (image may not have it yet)
BUILD_ROOTFS_IMG_SH := $(CURDIR_ABS)/build-rootfs-img.sh
BUILD_ROOTFS_IMG_VOL := $(if $(wildcard $(BUILD_ROOTFS_IMG_SH)),-v $(BUILD_ROOTFS_IMG_SH):/build/build-rootfs-img.sh:ro,)
# Bind-mount host build-dmc.sh for DDR devfreq module build
BUILD_DMC_SH := $(CURDIR_ABS)/build-dmc.sh
BUILD_DMC_VOL := $(if $(wildcard $(BUILD_DMC_SH)),-v $(BUILD_DMC_SH):/build/build-dmc.sh:ro,)
# Serial getty overlay for rootfs (ttyS2 @ 1500000); used when running make build
ROOTFS_OVERLAY_DIR := $(CURDIR_ABS)/rootfs-overlay-serial
ROOTFS_OVERLAY_VOL := $(if $(wildcard $(ROOTFS_OVERLAY_DIR)/etc/inittab),-v $(ROOTFS_OVERLAY_DIR):/build/rootfs-overlay-serial:ro,)

# Use existing image if present; build only when missing (same idea as make shell)
docker-image:
	@docker image inspect miyoo-flip-builder >/dev/null 2>&1 || $(MAKE) docker-build

all: docker-image docker-run

docker-build:
	@echo "Building Docker image..."
	@echo "Note: Only copying small scripts, large directories will be bind-mounted"
	docker build -t miyoo-flip-builder .

docker-run:
	@echo "Running build in Docker container..."
	@echo "Using bind mounts: output, Extra, .ccache, kernel (persistent), buildroot (persistent)"
	@mkdir -p output .ccache kernel buildroot .cursor
	@if [ ! -d "Extra" ]; then \
		echo "Error: Extra/ directory not found. Please ensure source files are extracted."; \
		exit 1; \
	fi
	docker run --rm \
		$(DTS_VOL) \
		$(ROOTFS_OVERLAY_VOL) \
		-v $(CURDIR_ABS)/output:/build/output \
		-v $(CURDIR_ABS)/Extra:/build/Extra:ro \
		-v $(CURDIR_ABS)/.ccache:/build/.ccache \
		-v $(CURDIR_ABS)/kernel:/build/kernel \
		-v $(CURDIR_ABS)/buildroot:/build/buildroot \
		-v $(CURDIR_ABS)/.cursor:/build/.cursor \
		miyoo-flip-builder

# Same volumes as docker-run; run an interactive shell so you can run any command (e.g. ./build-uboot.sh)
shell:
	@mkdir -p output .ccache kernel buildroot .cursor
	@if [ ! -d "Extra" ]; then \
		echo "Error: Extra/ directory not found. Please ensure source files are extracted."; \
		exit 1; \
	fi
	@echo "Starting interactive shell in builder container (workdir: /build)."
	@echo "Example: ./build-uboot.sh   or   ./build-kernel.sh   or   ./build-rootfs-buildroot.sh"
	docker run -it --rm \
		$(DTS_VOL) \
		$(ROOTFS_OVERLAY_VOL) \
		-v $(CURDIR_ABS)/output:/build/output \
		-v $(CURDIR_ABS)/Extra:/build/Extra:ro \
		-v $(CURDIR_ABS)/.ccache:/build/.ccache \
		-v $(CURDIR_ABS)/kernel:/build/kernel \
		-v $(CURDIR_ABS)/buildroot:/build/buildroot \
		-v $(CURDIR_ABS)/.cursor:/build/.cursor \
		miyoo-flip-builder \
		bash

build: docker-image docker-run

# Build kernel only (same container and volumes as make build; runs ./build-kernel.sh).
build-kernel: docker-image
	@mkdir -p output .ccache kernel buildroot .cursor
	@if [ ! -d "Extra" ]; then echo "Error: Extra/ directory not found."; exit 1; fi
	@echo "Building kernel in Docker..."
	@if [ -z "$(DTS_VOL)" ]; then \
		echo "WARNING: rk3566-miyoo-flip.dts not found at $(DTS_FILE). Run 'make build-kernel' from the project root (where the DTS lives). Container will use image DTS (may be stale)."; \
	else \
		echo "Using host DTS: $(DTS_FILE)"; \
	fi
	docker run --rm \
		$(DTS_VOL) \
		$(BUILD_KERNEL_VOL) \
		-v $(CURDIR_ABS)/output:/build/output \
		-v $(CURDIR_ABS)/Extra:/build/Extra:ro \
		-v $(CURDIR_ABS)/.ccache:/build/.ccache \
		-v $(CURDIR_ABS)/kernel:/build/kernel \
		-v $(CURDIR_ABS)/buildroot:/build/buildroot \
		-v $(CURDIR_ABS)/.cursor:/build/.cursor \
		miyoo-flip-builder \
		build-kernel.sh

# Build rootfs only (Buildroot; produces output/rootfs.squashfs and related). No kernel or U-Boot needed.
build-rootfs: docker-image
	@mkdir -p output .ccache kernel buildroot .cursor
	@if [ ! -d "Extra" ]; then echo "Error: Extra/ directory not found."; exit 1; fi
	@echo "Building rootfs (Buildroot) in Docker..."
	docker run --rm \
		$(ROOTFS_OVERLAY_VOL) \
		$(BUILD_ROOTFS_VOL) \
		-v $(CURDIR_ABS)/output:/build/output \
		-v $(CURDIR_ABS)/Extra:/build/Extra:ro \
		-v $(CURDIR_ABS)/.ccache:/build/.ccache \
		-v $(CURDIR_ABS)/kernel:/build/kernel \
		-v $(CURDIR_ABS)/buildroot:/build/buildroot \
		-v $(CURDIR_ABS)/.cursor:/build/.cursor \
		miyoo-flip-builder \
		bash /build/build-rootfs-buildroot.sh

# Build RTL8733BU WiFi driver module + install BT firmware. Requires kernel and rootfs built first.
build-wifi: docker-image
	@mkdir -p output .ccache kernel buildroot .cursor
	@if [ ! -d "Extra" ]; then echo "Error: Extra/ directory not found."; exit 1; fi
	@if [ ! -d "RTL8733BU" ]; then echo "Error: RTL8733BU/ not found. Run: make download-wifi"; exit 1; fi
	@echo "Building RTL8733BU WiFi/BT driver in Docker..."
	docker run --rm \
		-v $(CURDIR_ABS)/output:/build/output \
		-v $(CURDIR_ABS)/Extra:/build/Extra:ro \
		-v $(CURDIR_ABS)/.ccache:/build/.ccache \
		-v $(CURDIR_ABS)/kernel:/build/kernel \
		-v $(CURDIR_ABS)/buildroot:/build/buildroot \
		-v $(CURDIR_ABS)/.cursor:/build/.cursor \
		-v $(CURDIR_ABS)/RTL8733BU:/build/RTL8733BU \
		$(BUILD_WIFI_VOL) \
		miyoo-flip-builder \
		/build/build-rtl8733bu.sh

# Build Mali GPU driver (mali_kbase kernel module + libmali userspace). Requires kernel and rootfs built first.
build-mali: docker-image
	@mkdir -p output .ccache kernel buildroot .cursor
	@if [ ! -d "Extra" ]; then echo "Error: Extra/ directory not found."; exit 1; fi
	@if [ ! -d "mali-bifrost" ]; then echo "Error: mali-bifrost/ not found. Run: make download-mali"; exit 1; fi
	@if [ ! -d "libmali" ]; then echo "Error: libmali/ not found. Run: make download-mali"; exit 1; fi
	@echo "Building Mali GPU driver (mali_kbase + libmali) in Docker..."
	docker run --rm \
		-v $(CURDIR_ABS)/output:/build/output \
		-v $(CURDIR_ABS)/Extra:/build/Extra:ro \
		-v $(CURDIR_ABS)/.ccache:/build/.ccache \
		-v $(CURDIR_ABS)/kernel:/build/kernel \
		-v $(CURDIR_ABS)/buildroot:/build/buildroot \
		-v $(CURDIR_ABS)/.cursor:/build/.cursor \
		-v $(CURDIR_ABS)/mali-bifrost:/build/mali-bifrost \
		-v $(CURDIR_ABS)/libmali:/build/libmali \
		$(BUILD_MALI_VOL) \
		miyoo-flip-builder \
		/build/build-mali-kbase.sh

# Build DDR devfreq module (rk3568_dmc.ko). Requires kernel and rootfs built first.
build-dmc: docker-image
	@mkdir -p output .ccache kernel buildroot .cursor
	@if [ ! -d "Extra" ]; then echo "Error: Extra/ directory not found."; exit 1; fi
	@if [ ! -d "modules/rk3568_dmc" ]; then echo "Error: modules/rk3568_dmc/ not found."; exit 1; fi
	@echo "Building RK3568 DDR devfreq module in Docker..."
	docker run --rm \
		-v $(CURDIR_ABS)/output:/build/output \
		-v $(CURDIR_ABS)/Extra:/build/Extra:ro \
		-v $(CURDIR_ABS)/.ccache:/build/.ccache \
		-v $(CURDIR_ABS)/kernel:/build/kernel \
		-v $(CURDIR_ABS)/buildroot:/build/buildroot \
		-v $(CURDIR_ABS)/.cursor:/build/.cursor \
		-v $(CURDIR_ABS)/modules:/build/modules \
		$(BUILD_DMC_VOL) \
		miyoo-flip-builder \
		build-dmc.sh

# Build U-Boot only (produces output/uboot.img). No kernel or rootfs needed.
build-uboot: docker-image
	@mkdir -p output .ccache kernel buildroot .cursor
	@if [ ! -d "Extra" ]; then echo "Error: Extra/ directory not found."; exit 1; fi
	@echo "Building U-Boot in Docker..."
	docker run --rm \
		-v $(CURDIR_ABS)/output:/build/output \
		-v $(CURDIR_ABS)/Extra:/build/Extra:ro \
		-v $(CURDIR_ABS)/.ccache:/build/.ccache \
		-v $(CURDIR_ABS)/kernel:/build/kernel \
		-v $(CURDIR_ABS)/buildroot:/build/buildroot \
		-v $(CURDIR_ABS)/.cursor:/build/.cursor \
		miyoo-flip-builder \
		/build/build-uboot.sh

# Build boot.img using the container's mkbootimg (avoids host mkbootimg version issues). Writes to output/boot.img.
boot-img: docker-image
	@mkdir -p output .ccache kernel buildroot .cursor
	@if [ ! -d "Extra" ]; then echo "Error: Extra/ not found."; exit 1; fi
	@echo "Building boot.img in Docker (using container mkbootimg)..."
	docker run --rm \
		-v $(CURDIR_ABS)/output:/build/output \
		-v $(CURDIR_ABS)/Extra:/build/Extra:ro \
		-v $(CURDIR_ABS)/.ccache:/build/.ccache \
		-v $(CURDIR_ABS)/kernel:/build/kernel \
		-v $(CURDIR_ABS)/buildroot:/build/buildroot \
		-v $(CURDIR_ABS)/.cursor:/build/.cursor \
		-e BOOT_IMG=/build/output/boot.img \
		-e OUTPUT_DIR=/build/output \
		miyoo-flip-builder \
		/build/build-boot-img.sh
	@if [ -f output/boot.img ]; then cp -f output/boot.img boot.img; echo "boot.img ready (also copied to ./boot.img for flashing)."; fi

# Pack Buildroot target into rootfs.squashfs. Run after build-rootfs and after build-wifi/build-mali.
# Like boot-img for the boot partition—recreates rootfs image from current target (modules, firmware).
rootfs-img: docker-image
	@mkdir -p output .ccache kernel buildroot .cursor
	@if [ ! -d "Extra" ]; then echo "Error: Extra/ not found."; exit 1; fi
	@echo "Packing rootfs.squashfs in Docker..."
	docker run --rm \
		-v $(CURDIR_ABS)/output:/build/output \
		-v $(CURDIR_ABS)/Extra:/build/Extra:ro \
		-v $(CURDIR_ABS)/buildroot:/build/buildroot \
		$(BUILD_ROOTFS_IMG_VOL) \
		-e OUTPUT_DIR=/build/output \
		-e BUILDROOT_DIR=/build/buildroot \
		miyoo-flip-builder \
		build-rootfs-img.sh
	@if [ -f output/rootfs.squashfs ]; then echo "rootfs.squashfs ready. Flash rootfs partition."; fi

clean:
	@echo "Cleaning output directory..."
	rm -rf output/*.img output/*.dtb output/Image output/uboot.img

clean-kernel:
	@echo "Cleaning kernel build (use before make build to force full kernel rebuild)..."
	@if [ ! -f kernel/Makefile ]; then echo "No kernel/Makefile found (run make download-kernel first)."; exit 0; fi; \
	(cd kernel && make -j$$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1) clean) && echo "Kernel tree cleaned." || { echo ""; echo "Clean failed (often due to files owned by root from Docker). Fix with:"; echo "  sudo chown -R $$USER kernel"; echo "Then run 'make clean-kernel' again. Or remove and re-download: rm -rf kernel && make download-kernel"; exit 1; }

# Remove Buildroot target and images so next make build-rootfs rebuilds rootfs from scratch (overlay applied fresh). Keeps toolchain.
# Also remove host-gcc-final build dir to avoid "duplicate filename / already applied" patch errors when rebuilding.
clean-rootfs:
	@if [ -d buildroot/output ]; then \
		rm -rf buildroot/output/target buildroot/output/images; \
		rm -rf buildroot/output/build/host-gcc-final-* 2>/dev/null; \
		find buildroot/output/build -name '.stamp_target_installed' -delete 2>/dev/null; \
		find buildroot/output/per-package -type d -name 'target' -exec rm -rf {} + 2>/dev/null; true; \
		echo "Buildroot target, images, install stamps removed. Run 'make build-rootfs' to rebuild rootfs."; \
	else \
		echo "No buildroot/output found. Nothing to clean."; \
	fi

# Download fresh mainline kernel into kernel/ (git clone + apply patches). Remove kernel/ first to start over.
download-kernel:
	@$(SHELL) "$(CURDIR_ABS)/download-kernel.sh"

# Clone RTL8733BU WiFi driver and apply kernel 6.19 compat patch. Remove RTL8733BU/ first to start over.
download-wifi:
	@$(SHELL) "$(CURDIR_ABS)/download-wifi-driver.sh"

# Download Mali GPU driver (mali_kbase kernel module + libmali userspace). Remove mali-bifrost/ and libmali/ to start over.
download-mali:
	@$(SHELL) "$(CURDIR_ABS)/download-mali-driver.sh"

help:
	@echo "Miyoo Flip Build System (Buildroot-based)"
	@echo ""
	@echo "Targets:"
	@echo "  make build      - Build everything (reuses existing container image if present)"
	@echo "  make docker-build - Rebuild Docker image (run when you change Dockerfile or need fresh image)"
	@echo "  make docker-run  - Run build in Docker container"
	@echo "  make shell      - Start interactive shell in container (run any command, e.g. ./build-uboot.sh)"
	@echo "  make build-kernel - Build kernel only in Docker (reuses existing image; uses host rk3566-miyoo-flip.dts)"
	@echo "  make build-rootfs - Build rootfs only (Buildroot; output/rootfs.squashfs); no kernel/U-Boot needed"
	@echo "  make build-uboot - Build U-Boot only (output/uboot.img); no kernel/rootfs needed"
	@echo "  make build-wifi - Build RTL8733BU WiFi module + BT firmware (run after build-kernel and build-rootfs)"
	@echo "  make build-mali - Build Mali GPU driver (mali_kbase + libmali) (run after build-kernel and build-rootfs)"
	@echo "  make build-dmc  - Build DDR devfreq module (rk3568_dmc.ko) for DDR frequency scaling (run after build-kernel and build-rootfs)"
	@echo "  make boot-img   - Build boot.img from Image + DTB (run after build-kernel)"
	@echo "  make rootfs-img - Pack rootfs.squashfs from target (run after build-rootfs and build-wifi/build-mali)"
	@echo "  make clean      - Clean output files"
	@echo "  make clean-kernel - Clean kernel tree (full rebuild on next make build)"
	@echo "  make clean-rootfs - Remove Buildroot target/images; next make build-rootfs rebuilds rootfs from scratch (for serial shell, overlay applied fresh)"
	@echo "  make download-kernel - Download mainline Linux into kernel/ + apply display patches"
	@echo "  make download-wifi   - Clone RTL8733BU WiFi driver + apply kernel 6.19 compat patch"
	@echo "  make download-mali   - Download Mali GPU driver (ROCKNIX mali_kbase + libmali g24p0)"
	@echo ""
	@echo "To rebuild from scratch:"
	@echo "  rm -rf kernel RTL8733BU mali-bifrost libmali"
	@echo "  make download-kernel download-wifi download-mali"
	@echo "  make build-kernel && make build-rootfs && make build-wifi && make build-mali && make build-dmc && make boot-img && make rootfs-img"
	@echo ""
	@echo "Serial shell: For a login on UART you must use the Buildroot rootfs (with serial overlay). Run 'make build', then flash the rootfs partition with output/rootfs.squashfs. See docs/SERIAL-UART.md."
	@echo ""
	@echo "Rootfs uses Buildroot internal toolchain only (first build ~30-60 min longer)."
	@echo ""
	@echo "Bind-mounted directories (persist on host, no re-download):"
	@echo "  output/   - Build outputs (Image, .dtb, rootfs, etc.)"
	@echo "  kernel/   - Kernel source (populated by make download-kernel)"
	@echo "  buildroot/ - Buildroot source (clone once, reuse)"
	@echo "  .ccache/  - Compiler cache (faster rebuilds)"
	@echo ""
	@echo "DTS: Run 'make build-kernel' from the project root so host rk3566-miyoo-flip.dts is bind-mounted (otherwise image DTS is used)."
	@echo "     build-kernel forces DTB and panel-simple.o rebuild each run so DTS/kernel edits apply without make clean-kernel."
	@echo "     Use 'make clean-kernel' only for full kernel rebuild (e.g. after changing .config or many sources)."
	@echo "Inspect after a failed build:"
	@echo "  kernel/arch/arm64/boot/dts/rockchip/rk3566-miyoo-flip.dts"
	@echo "  kernel/arch/arm64/boot/dts/rockchip/Makefile"
	@echo ""
	@echo "See README.md for detailed instructions"
