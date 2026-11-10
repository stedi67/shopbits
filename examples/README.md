# Examples

`data/` is a small, **fictional** data set in the format `shopbits/snapshot`
loads: two sellers, one of them restricted to the countries it has rules for and
one selling worldwide. The sellers, rates and rule changes are made up.

    nim c -r tools/shopbits_check.nim examples/data
