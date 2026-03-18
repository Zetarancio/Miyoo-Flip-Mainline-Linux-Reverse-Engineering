# Boot chain (FIT and OP-TEE)

Distro-agnostic notes on the Miyoo Flip boot chain.

## SPI FIT layout (high level)

| Region | SPI Offset | Content |
|--------|------------|---------|
| Preloader | 0x000000–0x200000 | IDBLOCK + DDR init blob + stock SPL |
| U-Boot FIT | 0x300000+ | FIT image: ATF (BL31) + **OP-TEE (BL32)** + U-Boot + FDT |

## OP-TEE requirement

**Any U-Boot for this board must include OP-TEE (BL32) in the FIT image.** The boot chain expects ATF + OP-TEE + U-Boot; omitting OP-TEE is not supported by the stock BL31/loader design. Recent versions of BL31 actually include BL32.

For full details (segment addresses, BL31 DDR strings, DDR scaling), see [SPI image and boot chain (detailed)](spi-and-boot-chain.md).
