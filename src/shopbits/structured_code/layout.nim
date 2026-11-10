## Layouts of structured codes.
##
## A structured code is a fixed-width string whose characters are cut into
## named *slots*, like ``SHIREDXL``. A `Layout` describes one
## kind of such code. Everything else in this library (types, accessors,
## queries) is generated from layouts.
##
## Several kinds of codes can live next to each other, told apart by a fixed
## `prefix` of their first characters. A kind without a prefix is the fallback:
## it lists in `excluded` the prefixes that belong to the other kinds.

import std/strutils

type
  StructuredCodeError* = object of ValueError
    ## Raised when a string is not a valid code of the requested kind.

  SlotDef* = object
    name*: string
    width*: int
    valueType*: string
      ## Name of a ``distinct string`` type the slot value is wrapped in,
      ## or "" for a plain string.

  PrefixRule* = object
    ## Strings starting with `prefix`, unless they start with one of the
    ## `exceptions` (which are longer than the prefix).
    prefix*: string
    exceptions*: seq[string]

  Layout* = object
    name*: string
      ## Used in messages, e.g. "apparel".
    prefix*: string
      ## Leading characters every code of this kind starts with.
    prefixExcept*: seq[string]
      ## Strings that start with the prefix but are not of this kind.
    excluded*: seq[PrefixRule]
      ## Prefixes that belong to other kinds, so these are not of this kind.
    slots*: seq[SlotDef]

func slot*(name: string, width: int, valueType = ""): SlotDef =
  SlotDef(name: name, width: width, valueType: valueType)

func rule*(prefix: string, exceptions: varargs[string]): PrefixRule =
  PrefixRule(prefix: prefix, exceptions: @exceptions)

func codeLen*(layout: Layout): int =
  ## Length of a complete code.
  for s in layout.slots:
    result += s.width

func slotBoundaries*(layout: Layout): seq[int] =
  ## Offsets at which a slot starts.
  var offset = 0
  for s in layout.slots:
    result.add offset
    offset += s.width

func matches(s: string, rule: PrefixRule): bool =
  if not s.startsWith(rule.prefix): return false
  for e in rule.exceptions:
    if s.startsWith(e): return false
  true

func owns*(layout: Layout, s: string): bool =
  ## Does the start of `s` say that it is a code of this kind? This looks at
  ## the leading characters only, so it can be used for partial strings, too.
  if not s.startsWith(layout.prefix): return false
  for e in layout.prefixExcept:
    if s.startsWith(e): return false
  for rule in layout.excluded:
    if s.matches(rule): return false
  true

func familyLayouts*(layouts: openArray[Layout]): seq[Layout] =
  ## The layouts of a family of codes that live next to each other. A layout
  ## without a prefix is the fallback: it excludes the prefixes of all the others.
  for layout in layouts:
    var l = layout
    if l.prefix.len == 0:
      for other in layouts:
        if other.prefix.len > 0:
          l.excluded.add PrefixRule(prefix: other.prefix, exceptions: other.prefixExcept)
    result.add l

func isCodeChar*(c: char): bool =
  c in {'a'..'z', 'A'..'Z', '0'..'9', '_', '-', '+'}

func isValidCode*(layout: Layout, s: string): bool =
  ## True if `s` is a complete, well-formed code of this kind.
  if s.len != layout.codeLen or not layout.owns(s): return false
  for c in s:
    if not isCodeChar(c): return false
  true

func invalidCodeMessage*(layout: Layout, s: string): string =
  "'" & s & "' is not a valid " & layout.name & " code (expected " &
    $layout.codeLen & " characters from [A-Za-z0-9_+-]" &
    (if layout.prefix.len > 0: ", starting with '" & layout.prefix & "'" else: "") & ")"

proc checkSlotValue*(value: string, width: int, slotName: string) =
  ## Raises `StructuredCodeError` unless `value` fits into a slot.
  if value.len != width:
    raise newException(StructuredCodeError,
      "slot '" & slotName & "' needs exactly " & $width & " characters, got '" & value & "'")
  for c in value:
    if not isCodeChar(c):
      raise newException(StructuredCodeError,
        "slot '" & slotName & "' contains an invalid character in '" & value & "'")

func regexEscape(s: string): string =
  for c in s:
    if c == '+': result.add '\\'
    result.add c

func guardPattern*(layout: Layout): string =
  ## A regular expression lookahead that rejects the strings that start like
  ## codes of another kind, or "" if there is nothing to reject.
  var alternatives: seq[string]
  for rule in layout.excluded:
    var alternative = regexEscape(rule.prefix)
    if rule.exceptions.len > 0:
      var rests: seq[string]
      for e in rule.exceptions: rests.add regexEscape(e[rule.prefix.len .. ^1])
      alternative.add "(?!" & rests.join("|") & ")"
    alternatives.add alternative
  for e in layout.prefixExcept: alternatives.add regexEscape(e)
  if alternatives.len > 0: "(?!" & alternatives.join("|") & ")" else: ""
