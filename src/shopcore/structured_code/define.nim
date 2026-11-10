## Defining a kind of structured code from its layout.
##
## ``defineStructuredCode(SkuCode, SkuQuery, skuLayout)`` declares
##
## * ``SkuCode``, a ``distinct string``, and ``SkuQuery``, an alias of
##   ``Query[SkuCode]``
## * ``SkuCode.parse(s)`` / ``SkuCode.tryParse(s)``, which validate
## * one accessor per slot: ``code.color``, ``code.category``, ...; a slot
##   with a `valueType` returns that type instead of a string
## * one setter per slot that returns a changed copy: ``code.withColor("BLU")``
## * query constructors: ``SkuQuery.fromColor("RED")`` and
##   ``SkuQuery.fromSlots(color = "RED", size = "XL")``
## * the ``layoutOf(SkuCode)`` hook used by the generic procs in `query`
##
## ``skuLayout`` must be a ``const`` of type `Layout`. Types named as the
## `valueType` of a slot must be visible where the macro is called.
##
## The generated code uses ``Hash`` and ``Option``, so the module calling the
## macro needs ``std/hashes`` and ``std/options`` (the `structured_code` module
## exports them).
##
## Slots of a different kind of code do not exist: ``bookCode.size`` does not
## compile if book codes have no size slot.

import std/[macros, strutils]
import layout

macro defineImpl(codeType, queryType: untyped, layout: static Layout,
                 layoutName: static string): untyped =
  let
    ct = codeType.strVal
    qt = queryType.strVal
  var src = ""

  # the types
  src.add "type " & ct & "* = distinct string\n"
  src.add "type " & qt & "* = Query[" & ct & "]\n"
  src.add "template layoutOf*(T: typedesc[" & ct & "]): Layout = " & layoutName & "\n"
  src.add "proc `$`*(c: " & ct & "): string {.borrow.}\n"
  src.add "proc `==`*(a, b: " & ct & "): bool {.borrow.}\n"
  src.add "proc `<`*(a, b: " & ct & "): bool {.borrow.}\n"
  src.add "proc `<=`*(a, b: " & ct & "): bool {.borrow.}\n"
  src.add "proc hash*(c: " & ct & "): Hash {.borrow.}\n"
  src.add "proc len*(c: " & ct & "): int {.borrow.}\n"

  # parsing
  src.add "proc tryParse*(T: typedesc[" & ct & "], s: string): Option[" & ct & "] =\n"
  src.add "  if isValidCode(" & layoutName & ", s): some(" & ct & "(s)) else: none(" & ct & ")\n"
  src.add "proc parse*(T: typedesc[" & ct & "], s: string): " & ct & " =\n"
  src.add "  if not isValidCode(" & layoutName & ", s):\n"
  src.add "    raise newException(StructuredCodeError, invalidCodeMessage(" & layoutName & ", s))\n"
  src.add "  " & ct & "(s)\n"

  # slots
  var
    offset = 0
    fromSlotsParams = ""
    fromSlotsBody = ""
  for s in layout.slots:
    let
      name = s.name
      cap = capitalizeAscii(name)
      valueType = if s.valueType == "": "string" else: s.valueType
      lo = $offset
      hi = $(offset + s.width)
    src.add "proc " & name & "*(c: " & ct & "): " & valueType & " =\n"
    src.add "  " & valueType & "(string(c)[" & lo & " ..< " & hi & "])\n"
    src.add "proc with" & cap & "*(c: " & ct & ", value: " & valueType & "): " & ct & " =\n"
    src.add "  let v = string(value)\n"
    src.add "  checkSlotValue(v, " & $s.width & ", \"" & name & "\")\n"
    src.add "  var raw = string(c)\n"
    src.add "  raw[" & lo & " ..< " & hi & "] = v\n"
    src.add "  " & ct & "(raw)\n"
    src.add "proc from" & cap & "*(T: typedesc[" & qt & "], value: string): " & qt & " =\n"
    src.add "  cubeFrom[" & ct & "]([(" & lo & ", " & $s.width & ", value)])\n"
    fromSlotsParams.add ", " & name & " = \"\""
    fromSlotsBody.add "  if " & name & ".len > 0: parts.add (" & lo & ", " & $s.width & ", " & name & ")\n"
    offset += s.width

  src.add "proc fromSlots*(T: typedesc[" & qt & "]" & fromSlotsParams & "): " & qt & " =\n"
  src.add "  var parts: seq[tuple[offset, width: int, value: string]]\n"
  src.add fromSlotsBody
  src.add "  cubeFrom[" & ct & "](parts)\n"
  result = parseStmt(src)

template defineStructuredCode*(codeType, queryType, layoutConst: untyped) =
  ## Define a kind of code and its queries from a layout. See the module docs.
  defineImpl(codeType, queryType, layoutConst, astToStr(layoutConst))
