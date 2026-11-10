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
      structured_code.nim        fixed-width codes made of named slots, with typed queries
      structured_code/           its submodules
    tests/                     unit tests (unittest), one t*.nim file per module

## Using it

shopcore is a library. Import it from your code:

    import shopcore

### structured_code

`shopcore/structured_code` is a generic building block for identifiers such as
SKUs: fixed-width codes made of named slots. You describe the slots, and a
macro generates a distinct, validating type with typed accessors and a small
query algebra (`or`, `and`, `-`, `not`, `<=`, `in`):

    import shopcore/structured_code

    const skuLayout = Layout(name: "sku", slots: @[
      slot("category", 3), slot("color", 3), slot("size", 2)])
    defineStructuredCode(SkuCode, SkuQuery, skuLayout)

    let shirt = SkuCode.parse("SHIREDXL")
    assert shirt.color == "RED"
    assert $shirt.withColor("BLU") == "SHIBLUXL"

    let red = SkuQuery.fromColor("RED")
    let large = SkuQuery.fromSize("XL")
    assert shirt in (red and large)
    assert shirt notin (red - large)
    assert (red and large) <= red

Using a slot that does not exist, or mixing queries of different kinds of
codes, does not compile. `defineCodeFamily` handles several kinds of codes that
live next to each other (told apart by a prefix). See the module documentation
in `src/shopcore/structured_code.nim` for details.

To check that the library compiles without running anything:

    nim check src/shopcore.nim

## Running the tests

    nimble test

This compiles and runs every `tests/t*.nim` file. To run a single test file:

    nim c -r tests/tpm_decimals.nim
