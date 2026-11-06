# shopcore
shopcore is supposed to grow into the core of a shopping system. The system is mostly experimental and educational.

## Requirements

[Nim](https://nim-lang.org) 2.0 or newer (developed and tested with 2.4.0) and
its package manager `nimble`, which ships with Nim.
The easiest way to install both is [choosenim](https://github.com/nim-lang/choosenim)
or [Nim's installer](https://nim-lang.org/install.html).

## Project layout

    shopcore.nimble            package definition
    src/shopcore.nim           main module: money, prices, taxes
    src/shopcore/              submodules
      pm_decimals.nim            fixed precision decimals based on int64
      structured_string.nim      macro for fixed-width structured strings
    tests/                     unit tests (unittest), one t*.nim file per module

## Using it

shopcore is a library. Import it from your code:

    import shopcore

To check that the library compiles without running anything:

    nim check src/shopcore.nim

## Running the tests

    nimble test

This compiles and runs every `tests/t*.nim` file. To run a single test file:

    nim c -r tests/tpm_decimals.nim
