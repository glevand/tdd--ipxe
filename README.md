# TDD ipxe

UEFI PXE bootloader for the
[TDD Project](https://github.com/glevand/tdd-project).

For setup see the TDD Project
[README](https://github.com/glevand/tdd-project#ipxe-support).

## Usage

```sh
tdd-build-ipxe-images.sh - Generate TDD iPXE boot scripts and build iPXE images.
Usage: tdd-build-ipxe-images.sh [flags]
Option flags:
  -b --boot-scripts - Only generate boot scripts. Default: ''.
  -c --config-file  - Config file. Default: './src/ipxe-image.conf'.
  -h --help         - Show this help and exit.
  -o --output-dir   - Output directory. Default: './ipxe-out'.
  -v --verbose      - Verbose execution.
```
