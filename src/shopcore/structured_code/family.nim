## A family of kinds of codes, defined once.
##
## Often there are several kinds of codes that live next to each other and that
## are told apart by their first characters, like the kinds of product codes
## (apparel, books, ...).
## ``defineCodeFamily(CodeKind, AnyCode, kinds)``, where ``kinds`` is a ``const``
## sequence of `Layout`s, derives everything that ties the kinds together, so
## that the list of layouts is the only place where the kinds are named.
## For a layout named "apparel" it declares
##
## * ``ApparelCode`` and ``ApparelQuery`` (with everything
##   `defineStructuredCode` generates), and ``kindOf(ApparelCode)``
## * the enum member ``ckApparel`` of ``CodeKind``, and a field ``apparel`` of
##   the variant ``AnyCode``
##
## and for the family as a whole
##
## * ``CodeKind``, an enum with a member for each layout, in the order of the list
## * ``AnyCode``, a variant that holds a code of any kind, with ``toAnyCode`` for
##   each kind, ``raw``, ``$``, ``==``, ``hash``, ``AnyCode.parse(s)`` and
##   ``AnyCode.tryParse(s)``
## * ``CodeKind.dispatch(s)``: which kind a string belongs to, judging by its
##   first characters
## * ``layoutOf(kind)``, ``codeLen(kind)`` and ``isValidCode(kind, s)``
##
## Rules:
##
## * Layout names are the base of identifiers: letters and digits, starting with
##   a letter, and unique.
## * Exactly one layout has no prefix. It is the fallback kind; its `excluded`
##   prefixes are derived from the other layouts (`familyLayouts`).
## * The generated code uses ``Hash`` and ``Option``, so the module calling the
##   macro needs ``std/hashes`` and ``std/options``.
##
## The names ``Kind`` and ``Code``/``Query`` suffixes follow a convention, so the
## generated declarations do not appear literally in the source.

import std/[macros, strutils]
import layout

proc validate(layouts: seq[Layout]) =
  if layouts.len == 0:
    error("a code family needs at least one layout")
  var
    names: seq[string]
    fallbacks = 0
  for l in layouts:
    if l.name.len == 0 or not l.name[0].isAlphaAscii or not l.name.allCharsInSet(Letters + Digits):
      error("layout name '" & l.name & "' must consist of letters and digits and start with a letter")
    if l.name in names:
      error("duplicate layout name '" & l.name & "'")
    names.add l.name
    if l.prefix.len == 0: inc fallbacks
  if fallbacks != 1:
    error("a code family needs exactly one layout without a prefix (the fallback), found " & $fallbacks)

macro defineFamilyImpl(kindType, anyType: untyped, kinds: static seq[Layout],
                       kindsName: static string, memberPrefix: static string): untyped =
  validate(kinds)
  let
    kt = kindType.strVal
    at = anyType.strVal
    table = kt & "Layouts"
    lens = kt & "Lens"
  proc cap(l: Layout): string = capitalizeAscii(l.name)
  proc member(l: Layout): string = memberPrefix & cap(l)

  var
    src = ""
    fallback = ""
  for l in kinds:
    if l.prefix.len == 0: fallback = member(l)

  # the enum, and the layouts with the exclusions of the fallback derived
  src.add "type " & kt & "* = enum\n"
  for l in kinds: src.add "  " & member(l) & " = \"" & l.name & "\"\n"
  src.add "const " & table & " = familyLayouts(" & kindsName & ")\n"
  src.add "const " & lens & ": array[" & kt & ", int] = [\n"
  for l in kinds: src.add "  " & member(l) & ": " & $l.codeLen & ",\n"
  src.add "]\n"
  src.add "func layoutOf*(kind: " & kt & "): Layout = " & table & "[ord(kind)]\n"
  src.add "func codeLen*(kind: " & kt & "): int = " & lens & "[kind]\n"
  src.add "func isValidCode*(kind: " & kt & ", s: string): bool =\n"
  src.add "  " & table & "[ord(kind)].isValidCode(s)\n"
  src.add "func dispatch*(T: typedesc[" & kt & "], s: string): " & kt & " =\n"
  src.add "  for kind in " & kt & ":\n"
  src.add "    if " & table & "[ord(kind)].prefix.len > 0 and " & table & "[ord(kind)].owns(s):\n"
  src.add "      return kind\n"
  src.add "  " & fallback & "\n"

  # the code type of each kind
  for i, l in kinds:
    src.add "defineStructuredCode(" & cap(l) & "Code, " & cap(l) & "Query, " & table & "[" & $i & "])\n"
    src.add "template kindOf*(T: typedesc[" & cap(l) & "Code]): " & kt & " = " & member(l) & "\n"

  # a code of any kind
  src.add "type " & at & "* = object\n"
  src.add "  case kind*: " & kt & "\n"
  for l in kinds:
    src.add "  of " & member(l) & ": " & l.name & "*: " & cap(l) & "Code\n"
  for l in kinds:
    src.add "func to" & at & "*(c: " & cap(l) & "Code): " & at & " =\n"
    src.add "  " & at & "(kind: " & member(l) & ", " & l.name & ": c)\n"
  src.add "func raw*(c: " & at & "): string =\n"
  src.add "  case c.kind\n"
  for l in kinds:
    src.add "  of " & member(l) & ": string(c." & l.name & ")\n"
  src.add "func `$`*(c: " & at & "): string = c.raw\n"
  src.add "func `==`*(a, b: " & at & "): bool = a.kind == b.kind and a.raw == b.raw\n"
  src.add "func hash*(c: " & at & "): Hash = hash(c.raw)\n"
  src.add "proc tryParse*(T: typedesc[" & at & "], s: string): Option[" & at & "] =\n"
  src.add "  let kind = " & kt & ".dispatch(s)\n"
  src.add "  if not isValidCode(kind, s): return none(" & at & ")\n"
  src.add "  case kind\n"
  for l in kinds:
    src.add "  of " & member(l) & ": some(to" & at & "(" & cap(l) & "Code(s)))\n"
  src.add "proc parse*(T: typedesc[" & at & "], s: string): " & at & " =\n"
  src.add "  let code = " & at & ".tryParse(s)\n"
  src.add "  if code.isNone:\n"
  src.add "    raise newException(StructuredCodeError, invalidCodeMessage(layoutOf(" & kt & ".dispatch(s)), s))\n"
  src.add "  code.get\n"
  result = parseStmt(src)

template defineCodeFamily*(kindType, anyType, kinds: untyped, memberPrefix: static string = "ck") =
  ## Define a family of kinds of codes from a ``const`` sequence of layouts.
  ## See the module docs. The members of the kind enum start with `memberPrefix`.
  defineFamilyImpl(kindType, anyType, kinds, astToStr(kinds), memberPrefix)
