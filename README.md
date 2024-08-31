A quick and dirty signal generator for the STM32U0 series (because I had a NUCLEO board). Could be easily adapted to other boards with DAC.

You need to have pyOCD installed (`python3 -m pip install -U pyocd`) for flashing. Debug is also supported
using pyOCD and the included VS Code runner scripts.

Thanks to https://github.com/haydenridd/stm32-baremetal-zig for the example on how to compile Zig into STM32 devices!
