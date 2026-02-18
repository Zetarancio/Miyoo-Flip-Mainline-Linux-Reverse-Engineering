# Out-of-tree Makefile for rk3568_dmc DDR devfreq module
obj-m := rk3568_dmc.o

KDIR ?= /build/kernel
ARCH ?= arm64
CROSS_COMPILE ?= aarch64-buildroot-linux-gnu-

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) clean
