## The query algebra.
##
## A query describes a *set of codes*. The simplest query is a *pattern*: one
## character per code position, where ``?`` matches any character
## (``SHIRED??``). Queries are combined with the set operations
##
## * ``a or b``  union
## * ``a and b`` intersection
## * ``a - b``   difference
## * ``not a``   complement
##
## These operators have the same relative precedence as ``|``, ``&`` and ``-``
## have in Python (``-`` binds tighter than ``and``, which binds tighter than
## ``or``). That is why ``and``/``or`` are used instead of ``&``/``|``: in Nim
## ``&`` would bind *weaker* than ``|``.
##
## Beware that in Nim the comparison operators (``<=``, ``in``, ``==``) bind
## *tighter* than ``and``/``or`` (the opposite of Python), so always put
## parentheses around a query that is an operand of a comparison:
## ``x <= (a or b)``. Forgetting them is a type error, not a wrong result.
##
## Queries are typed: a ``Query[C]`` only ever contains codes of type ``C``,
## and combining it with a ``Query[D]`` does not compile.
##
## The types ``C`` are defined with `defineStructuredCode`; the procs here that
## need to know about the layout of ``C`` (`anyQuery`, `parseQuery`, ...) get it
## from the ``layoutOf`` hook that macro defines for each type.
##
## Properties of this implementation:
##
## * ``<=`` (subset) is decided *exactly*, for every combination of operators.
## * Wildcards work per character, not only at the end of a slot.
## * ``==`` compares the structure of two queries (after simplification), use
##   `equivalent` to compare the sets they describe.

import std/[hashes, strutils]
import layout

const
  Wildcard* = '?'
  Unassigned = '\0'  # internal markers, never part of a pattern
  OtherChar = '\1'

type
  QueryError* = object of ValueError
  IncompatibleQueryError* = object of QueryError
    ## A query string describes another kind of code than requested.
  QueryStringError* = object of QueryError
    ## A query string could not be parsed.

  NodeKind* = enum
    nkAny, nkNull, nkPattern, nkUnion, nkMinus

  QueryNode* = ref object
    ## Untyped query tree. Nodes are immutable, so they can be shared freely.
    width*: int  ## length of the codes in the set
    case nk*: NodeKind
    of nkPattern: pattern*: string
    of nkUnion, nkMinus: left*, right*: QueryNode
    of nkAny, nkNull: discard

  Query*[C] = object
    ## A set of codes of type `C`. A default constructed query is empty.
    node*: QueryNode

# ---------------------------------------------------------------------------
# nodes

func newAny*(width: int): QueryNode = QueryNode(width: width, nk: nkAny)
func newNull*(width: int): QueryNode = QueryNode(width: width, nk: nkNull)
func newPattern*(pattern: string): QueryNode =
  QueryNode(width: pattern.len, nk: nkPattern, pattern: pattern)

func isNull*(n: QueryNode): bool = n.nk == nkNull
func isAny*(n: QueryNode): bool = n.nk == nkAny

func sameStructure*(a, b: QueryNode): bool =
  if a == b: return true  # same object
  if a.width != b.width or a.nk != b.nk: return false
  case a.nk
  of nkAny, nkNull: true
  of nkPattern: a.pattern == b.pattern
  of nkUnion, nkMinus: sameStructure(a.left, b.left) and sameStructure(a.right, b.right)

func `$`*(n: QueryNode): string =
  case n.nk
  of nkAny: "<All>"
  of nkNull: "<EmptySet>"
  of nkPattern: n.pattern
  of nkUnion: "<QueryUnion " & $n.left & " " & $n.right & ">"
  of nkMinus: "<QueryMinus " & $n.left & " " & $n.right & ">"

func hash*(n: QueryNode): Hash =
  case n.nk
  of nkAny: hash(n.width) !& 1
  of nkNull: hash(n.width) !& 2
  of nkPattern: hash(n.pattern)
  of nkUnion: hash(n.left) + hash(n.right)  # a or b and b or a hash alike
  of nkMinus: hash(n.left) - hash(n.right)

# ---------------------------------------------------------------------------
# set operations

func patternContains(pattern, code: string): bool =
  if pattern.len != code.len: return false
  for i in 0 ..< pattern.len:
    if pattern[i] != Wildcard and pattern[i] != code[i]:
      return false
  true

func mergePatterns(a, b: string, merged: var string): bool =
  ## Intersection of two patterns. False if they are disjoint.
  merged = newString(a.len)
  for i in 0 ..< a.len:
    if a[i] == Wildcard: merged[i] = b[i]
    elif b[i] == Wildcard or a[i] == b[i]: merged[i] = a[i]
    else: return false
  true

func union*(a, b: QueryNode): QueryNode =
  if a.isNull: return b
  if b.isNull: return a
  if a.isAny or b.isAny: return newAny(a.width)
  if sameStructure(a, b): return a
  QueryNode(width: a.width, nk: nkUnion, left: a, right: b)

func difference*(a, b: QueryNode): QueryNode

func intersection*(a, b: QueryNode): QueryNode =
  if a.isNull or b.isNull: return newNull(a.width)
  if a.isAny: return b
  if b.isAny: return a
  # Distribute over unions and differences so that only patterns are left.
  if a.nk == nkUnion:
    return union(intersection(a.left, b), intersection(a.right, b))
  if b.nk == nkUnion:
    return union(intersection(a, b.left), intersection(a, b.right))
  if a.nk == nkMinus:
    return difference(intersection(a.left, b), intersection(a.right, b))
  if b.nk == nkMinus:
    return difference(intersection(a, b.left), intersection(a, b.right))
  var merged: string
  if mergePatterns(a.pattern, b.pattern, merged): newPattern(merged)
  else: newNull(a.width)

func difference*(a, b: QueryNode): QueryNode =
  if a.isNull or b.isNull: return a
  if b.isAny: return newNull(a.width)
  if sameStructure(a, b): return newNull(a.width)
  if a.nk == nkPattern and intersection(a, b).isNull: return a  # disjoint
  QueryNode(width: a.width, nk: nkMinus, left: a, right: b)

func complement*(a: QueryNode): QueryNode = difference(newAny(a.width), a)

func contains*(n: QueryNode, code: string): bool =
  ## Is `code` a member of the set? `code` is a complete code.
  case n.nk
  of nkAny: true
  of nkNull: false
  of nkPattern: patternContains(n.pattern, code)
  of nkUnion: n.left.contains(code) or n.right.contains(code)
  of nkMinus: n.left.contains(code) and not n.right.contains(code)

# ---------------------------------------------------------------------------
# deciding emptiness and inclusion
#
# A set is empty if no code is a member. Only the characters that occur in the
# patterns of the expression (plus "any other character") matter at each
# position, so we search over those, pruning with three valued logic.

type Tri = enum tFalse, tUnknown, tTrue

func and3(a, b: Tri): Tri =
  if a == tFalse or b == tFalse: tFalse
  elif a == tTrue and b == tTrue: tTrue
  else: tUnknown

func or3(a, b: Tri): Tri =
  if a == tTrue or b == tTrue: tTrue
  elif a == tFalse and b == tFalse: tFalse
  else: tUnknown

func not3(a: Tri): Tri =
  case a
  of tFalse: tTrue
  of tTrue: tFalse
  of tUnknown: tUnknown

func evalPartial(n: QueryNode, assign: string): Tri =
  ## Membership of every code that agrees with the partial assignment.
  case n.nk
  of nkAny: result = tTrue
  of nkNull: result = tFalse
  of nkPattern:
    result = tTrue
    for i in 0 ..< n.pattern.len:
      let p = n.pattern[i]
      if p == Wildcard: continue
      if assign[i] == Unassigned: result = tUnknown
      elif assign[i] != p: return tFalse
  of nkUnion:
    result = or3(evalPartial(n.left, assign), evalPartial(n.right, assign))
  of nkMinus:
    result = and3(evalPartial(n.left, assign), not3(evalPartial(n.right, assign)))

func collectPatterns(n: QueryNode, patterns: var seq[string]) =
  case n.nk
  of nkPattern: patterns.add n.pattern
  of nkUnion, nkMinus:
    collectPatterns(n.left, patterns)
    collectPatterns(n.right, patterns)
  of nkAny, nkNull: discard

func isEmpty*(n: QueryNode): bool =
  ## True if no code is a member of the set (exact).
  let width = n.width
  var patterns: seq[string]
  collectPatterns(n, patterns)
  var candidates = newSeq[seq[char]](width)
  for pattern in patterns:
    for i in 0 ..< width:
      if pattern[i] != Wildcard and pattern[i] notin candidates[i]:
        candidates[i].add pattern[i]
  var positions: seq[int]
  for i in 0 ..< width:
    if candidates[i].len > 0: positions.add i

  var assign = newString(width)  # filled with Unassigned
  proc search(idx: int): bool =
    ## Is there a member among the codes agreeing with `assign`?
    case evalPartial(n, assign)
    of tFalse: return false
    of tTrue: return true
    of tUnknown: discard
    if idx >= positions.len: return false  # cannot happen, everything is decided
    let pos = positions[idx]
    for ch in candidates[pos]:
      assign[pos] = ch
      if search(idx + 1): return true
    assign[pos] = OtherChar
    if search(idx + 1): return true
    assign[pos] = Unassigned
    false
  not search(0)

func isSubset*(a, b: QueryNode): bool =
  ## Is every member of `a` also a member of `b`? (exact)
  difference(a, b).isEmpty

func equivalent*(a, b: QueryNode): bool =
  isSubset(a, b) and isSubset(b, a)

# ---------------------------------------------------------------------------
# regular expressions

func regexBody(n: QueryNode): string =
  case n.nk
  of nkAny: result = repeat('.', n.width)
  of nkNull: result = "(?!)"  # never matches
  of nkPattern:
    for c in n.pattern:
      case c
      of Wildcard: result.add '.'
      of '+': result.add "\\+"
      else: result.add c
  of nkUnion:
    result = "(?:" & regexBody(n.left) & ")|(?:" & regexBody(n.right) & ")"
  of nkMinus:
    result = "(?!" & regexBody(n.right) & ")(?:" & regexBody(n.left) & ")"

func toRegexPattern*(n: QueryNode, guard = ""): string =
  ## A regular expression (PCRE/POSIX ARE syntax, with lookahead) that matches
  ## exactly the complete codes in the set. `guard` is a lookahead put in front
  ## (see `guardPattern`).
  "^" & guard & "(?:" & regexBody(n) & ")$"

# ---------------------------------------------------------------------------
# parsing and building patterns

func isQueryChar(c: char): bool = isCodeChar(c) or c == Wildcard

func overlayPrefix(layout: Layout, pattern: var string) =
  ## Pin the fixed prefix of the layout.
  for i in 0 ..< layout.prefix.len:
    pattern[i] = layout.prefix[i]

proc patternFromString*(layout: Layout, s: string): QueryNode =
  ## Parse a query string such as ``SHIRED`` or ``SHI???XL``.
  ## ``.`` and ``?`` are wildcards. The string may end at any slot boundary, the
  ## rest is filled up with wildcards. Raises `IncompatibleQueryError` if the
  ## string starts like a code of another kind.
  if not layout.owns(s):
    raise newException(IncompatibleQueryError,
      "'" & s & "' is not a " & layout.name & " query")
  var pattern = newStringOfCap(layout.codeLen)
  for c in s:
    if c == '.': pattern.add Wildcard
    elif isQueryChar(c): pattern.add c
    else:
      raise newException(QueryStringError,
        "invalid character '" & c & "' in query string '" & s & "'")
  if pattern.len != layout.codeLen and pattern.len notin layout.slotBoundaries:
    raise newException(QueryStringError,
      "query string '" & s & "' does not end at a slot boundary")
  pattern.add repeat(Wildcard, layout.codeLen - pattern.len)
  newPattern(pattern)

proc patternFromSlots*(layout: Layout,
                    parts: openArray[tuple[offset, width: int, value: string]]): QueryNode =
  ## Build a pattern from slot values. Everything not given is a wildcard.
  var pattern = repeat(Wildcard, layout.codeLen)
  overlayPrefix(layout, pattern)
  for (offset, width, value) in parts:
    if value.len != width:
      raise newException(QueryStringError,
        "slot value '" & value & "' needs exactly " & $width & " characters")
    for i, c in value:
      if c == '.': pattern[offset + i] = Wildcard
      elif isQueryChar(c): pattern[offset + i] = c
      else:
        raise newException(QueryStringError,
          "invalid character '" & c & "' in slot value '" & value & "'")
  newPattern(pattern)

# ---------------------------------------------------------------------------
# typed queries

func nodeOf*[C](q: Query[C]): QueryNode =
  mixin layoutOf
  if q.node.isNil: newNull(layoutOf(C).codeLen) else: q.node

func anyQuery*[C](): Query[C] =
  ## The query matching every code of type `C`.
  mixin layoutOf
  Query[C](node: newAny(layoutOf(C).codeLen))

func nullQuery*[C](): Query[C] =
  ## The query matching no code at all.
  mixin layoutOf
  Query[C](node: newNull(layoutOf(C).codeLen))

func toQuery*[C](code: C): Query[C] =
  ## The query matching exactly one code.
  Query[C](node: newPattern(string(code)))

proc patternFrom*[C](parts: openArray[tuple[offset, width: int, value: string]]): Query[C] =
  mixin layoutOf
  Query[C](node: patternFromSlots(layoutOf(C), parts))

proc parseQuery*[C](s: string): Query[C] =
  ## Parse a query string, e.g. ``parseQuery[SkuCode]("SHIRED")``.
  ## Raises `IncompatibleQueryError` if the string is about another kind of code.
  mixin layoutOf
  Query[C](node: patternFromString(layoutOf(C), s))

func `or`*[C](a, b: Query[C]): Query[C] =
  Query[C](node: union(a.nodeOf, b.nodeOf))

func `and`*[C](a, b: Query[C]): Query[C] =
  Query[C](node: intersection(a.nodeOf, b.nodeOf))

func `-`*[C](a, b: Query[C]): Query[C] =
  Query[C](node: difference(a.nodeOf, b.nodeOf))

func `not`*[C](a: Query[C]): Query[C] =
  Query[C](node: complement(a.nodeOf))

func contains*[C](q: Query[C], code: C): bool =
  ## ``code in query``
  q.nodeOf.contains(string(code))

func `<=`*[C](a, b: Query[C]): bool =
  ## Subset: every code matched by `a` is matched by `b`.
  ## ``a >= b`` is the superset check.
  isSubset(a.nodeOf, b.nodeOf)

func toRegexPattern*[C](q: Query[C]): string =
  ## An anchored regular expression matching exactly the codes in the query.
  mixin layoutOf
  toRegexPattern(q.nodeOf, layoutOf(C).guardPattern)

func isEmpty*[C](q: Query[C]): bool = q.nodeOf.isEmpty
func equivalent*[C](a, b: Query[C]): bool = equivalent(a.nodeOf, b.nodeOf)
func `==`*[C](a, b: Query[C]): bool = sameStructure(a.nodeOf, b.nodeOf)
func `$`*[C](q: Query[C]): string = $q.nodeOf
func hash*[C](q: Query[C]): Hash = hash(q.nodeOf)
