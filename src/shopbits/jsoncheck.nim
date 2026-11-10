## Strict validation of parsed JSON, collecting all the problems.
##
## The helpers check one field of a JSON object at a time and add an `Issue` for
## everything that is wrong (instead of stopping at the first problem), so that a
## file or a request can be reported on as a whole. They are used for the data
## files (`shopbits/snapshot`) and for requests (`shopbits/verify`).

import std/[json, options, strutils]
import date

type
  Issue* = object
    ## One problem with some data.
    file*: string   ## the file, relative to the data directory; empty if there is none
    where*: string  ## the position in the file or request, e.g. ``rules[1].rate``
    message*: string

func `$`*(issue: Issue): string =
  result = issue.file
  if issue.where.len > 0:
    if result.len > 0: result.add ": "
    result.add issue.where
  if result.len > 0: result.add ": "
  result.add issue.message

proc problem*(issues: var seq[Issue], file, where, message: string) =
  issues.add Issue(file: file, where: where, message: message)

func describe*(kind: JsonNodeKind): string =
  case kind
  of JString: "a string"
  of JInt: "an integer"
  of JFloat: "a number"
  of JBool: "a boolean"
  of JNull: "null"
  of JObject: "an object"
  of JArray: "an array"

func at*(where, key: string): string =
  if where.len > 0: where & "." & key else: key

proc checkFields*(node: JsonNode, allowed: openArray[string], file, where: string,
                 issues: var seq[Issue]) =
  for key, _ in node.pairs:
    if key notin allowed:
      problem(issues, file, where.at(key),
              "unknown field (allowed: " & allowed.join(", ") & ")")

proc stringField*(node: JsonNode, key: string, required: bool, file, where: string,
                 issues: var seq[Issue]): Option[string] =
  ## A non-empty string field.
  let position = where.at(key)
  if not node.hasKey(key):
    if required: problem(issues, file, position, "required, but missing")
    return none(string)
  let value = node[key]
  if value.kind != JString:
    problem(issues, file, position, "must be a string, not " & describe(value.kind))
  elif value.getStr.len == 0:
    problem(issues, file, position, "must not be empty")
  else:
    return some(value.getStr)
  none(string)

func parseExact*[T: enum](s: string): Option[T] =
  ## The enum value whose name is exactly `s` (no style insensitivity).
  for value in T:
    if $value == s: return some(value)
  none(T)

func names*[T: enum](): string =
  for value in T:
    if result.len > 0: result.add ", "
    result.add $value

proc enumField*[T: enum](node: JsonNode, key: string, required: bool, file, where: string,
                        issues: var seq[Issue]): Option[T] =
  let text = stringField(node, key, required, file, where, issues)
  if text.isNone: return none(T)
  result = parseExact[T](text.get)
  if result.isNone:
    problem(issues, file, where.at(key),
            "'" & text.get & "' is not valid (expected one of: " & names[T]() & ")")

proc setField*[T: enum](node: JsonNode, key: string, spellings: openArray[(string, T)],
                       file, where: string, issues: var seq[Issue]): Option[set[T]] =
  ## A non-empty array of names, as a set. `spellings` maps the names to values.
  let position = where.at(key)
  if not node.hasKey(key): return none(set[T])
  let array = node[key]
  if array.kind != JArray:
    problem(issues, file, position, "must be an array, not " & describe(array.kind))
    return none(set[T])
  if array.len == 0:
    problem(issues, file, position, "must not be empty (leave the field out for all)")
    return none(set[T])
  var found: set[T]
  var ok = true
  for i, item in array.elems:
    let itemPosition = position & "[" & $i & "]"
    var matched = false
    if item.kind == JString:
      for (name, value) in spellings:
        if name == item.getStr:
          found.incl value
          matched = true
    if not matched:
      ok = false
      var allowed: seq[string]
      for (name, _) in spellings: allowed.add name
      problem(issues, file, itemPosition,
              "is not valid (expected one of: " & allowed.join(", ") & ")")
  if ok: some(found) else: none(set[T])

proc dateField*(node: JsonNode, key: string, file, where: string,
               issues: var seq[Issue]): Option[Date] =
  let text = stringField(node, key, false, file, where, issues)
  if text.isNone: return none(Date)
  result = tryParseDate(text.get)
  if result.isNone:
    problem(issues, file, where.at(key),
            "'" & text.get & "' is not a date in the format YYYY-MM-DD")

