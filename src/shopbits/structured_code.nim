## structured_code: fixed-width codes made of named slots, and queries over them.
##
## A *structured code* is a fixed-width string like ``SHIREDXL``
## whose characters are grouped into named slots. This library is generic: you
## describe a kind of code with a `Layout`, and `defineStructuredCode` declares a
## distinct type for it with validating parsing, typed slot accessors and
## setters, and a typed query algebra:
##
## .. code-block:: nim
##   import shopbits/structured_code
##
##   const colorLayout = Layout(name: "color", slots: @[
##     slot("hue", 3), slot("shade", 2)])
##   defineStructuredCode(ColorCode, ColorQuery, colorLayout)
##
##   let red = ColorCode.parse("red01")
##   assert red.hue == "red"
##   assert red in ColorQuery.fromHue("red")
##   assert red notin (ColorQuery.fromHue("red") - ColorQuery.fromShade("01"))
##
## Several kinds of codes can be defined, which then are different types, so
## that slots that don't exist for a kind and queries mixing kinds do not
## compile.
##
## * `layout`: `Layout`, validation
## * `query`: the query algebra
## * `define`: `defineStructuredCode`
## * `family`: `defineCodeFamily`, for several kinds of codes that live next to
##   each other (derives the kind enum, a variant holding any kind, dispatching)
##
## The generated code uses `Hash` and `Option`, which are exported for that reason.

import std/[hashes, options]
import structured_code/[layout, query, define, family]
export hashes, options
export layout, query, define, family
