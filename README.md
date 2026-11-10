# shopbits
shopbits is supposed to grow into a collection of building blocks for shopping systems. It is mostly experimental and educational.

## Requirements

[Nim](https://nim-lang.org) 2.0 or newer (developed and tested with 2.4.0) and
its package manager `nimble`, which ships with Nim.
The easiest way to install both is [choosenim](https://github.com/nim-lang/choosenim)
or [Nim's installer](https://nim-lang.org/install.html).

## Project layout

    shopbits.nimble            package definition
    src/shopbits.nim           main module: money, prices, taxes
    src/shopbits/              submodules
      pm_decimals.nim            fixed precision decimals based on int64
      tax_nexus.nim              which tax rules apply, by seller and delivery source
      date.nim                   calendar dates (effective dates of rules)
      snapshot.nim               loads and validates reference data from text files
      sha256.nim                 content hash for snapshot ids
      structured_code.nim        fixed-width codes made of named slots, with typed queries
      structured_code/           its submodules
    tools/shopbits_check.nim   checks a data directory, e.g. for CI of a data repository
    examples/data/             a small fictional data set in the format snapshot.nim loads
    tests/                     unit tests (unittest), one t*.nim file per module

## Using it

shopbits is a library. Import it from your code:

    import shopbits

### Reference data

`shopbits/snapshot` loads reference data (for now the tax nexuses and their rules)
from a directory of plain JSON files, for example a git repository, and validates it
strictly: unknown fields and files, bad values and duplicates are all reported
together, each with its file and position. The loaded `Snapshot` is immutable and has
an `id`, the SHA-256 of the contents of its files, so a result can be traced to
exactly the data it came from. Rules can be effective for a period (`validFrom`,
`validUntil`), and every tax lookup takes the day it is for.

    nim c -r tools/shopbits_check.nim examples/data

The file format is described in the documentation at the top of
`src/shopbits/snapshot.nim`; `examples/data` is a small fictional example.

### structured_code

`shopbits/structured_code` is a generic building block for identifiers such as
SKUs: fixed-width codes made of named slots. You describe the slots, and a
macro generates a distinct, validating type with typed accessors and a small
query algebra (`or`, `and`, `-`, `not`, `<=`, `in`):

    import shopbits/structured_code

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
in `src/shopbits/structured_code.nim` for details.

To check that the library compiles without running anything:

    nim check src/shopbits.nim

## Running the tests

    nimble test

This compiles and runs every `tests/t*.nim` file. To run a single test file:

    nim c -r tests/tpm_decimals.nim
