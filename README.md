A quick and dirty signal generator for the STM32U0 series (because I had a NUCLEO board). Could be easily adapted to other boards with DAC.

Register maps have been generated using microzig's regz, and are included in the project. To regenerate these files, download the SVD file from `https://github.com/modm-io/cmsis-svd-stm32/`, regz from `https://github.com/ZigEmbeddedGroup/microzig/blob/main/tools/regz`, build the tool and run it `regz [svd] > src/stm32u083.zig`.

Thanks to https://github.com/haydenridd/stm32-baremetal-zig for the example on how to compile Zig into STM32 devices!
