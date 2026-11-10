## Reference data snapshots: loading and validating the data of a shop.
##
## A `Snapshot` is the reference data a shop works with (for now the tax nexuses
## with their rules), loaded from a directory of plain text files, typically a
## git repository. It is immutable, and has an `id` derived from the *content* of
## the files, so a result can always be traced back to exactly the data it was
## computed from.
##
## ::
##   data/
##     manifest.json            {"schema": 1, "name": "optional name"}
##     nexuses/
##       acme-gb.json           one nexus per file
##       acme-de.json
##
## A nexus file looks like this (all rates are strings, never numbers):
##
## ::
##   {
##     "seller": "acme", "source": "de", "fallback": "reject",
##     "rules": [
##       {"tax": "vat", "destination": "de", "rate": "0.19", "validUntil": "2026-12-31"},
##       {"tax": "vat", "destination": "de", "rate": "0.21", "validFrom": "2027-01-01"},
##       {"tax": "levy", "destination": "de", "goodsTypes": ["physical"], "rate": "0.02"},
##       {"destination": "gb", "rate": "0.00", "treatment": "importDueByCustomer",
##        "reason": "import tax is payable by the customer"}
##     ]
##   }
##
## Per rule: ``destination`` and ``rate`` are required; ``tax`` (default
## "tax"), ``goodsTypes`` (``physical``, ``software``, ``book``; default all),
## ``businessTypes`` (``b2c``, ``b2b``; default both), ``treatment`` (see
## `TaxTreatment`; default ``standard``), ``reason``, ``validFrom`` and
## ``validUntil`` (``YYYY-MM-DD``, both inclusive) are optional.
##
## Loading is **strict**: unknown fields, unknown files and directories, bad
## values and duplicates are errors, not silently ignored (a typo in a directory
## name must not mean that its data is missing). All problems are collected and
## reported together, each with the file and the position in it, so that one run
## of a check shows everything that needs fixing.
##
## The `id` is the SHA-256 of the names and contents of all the files (in order of
## their names, with line endings normalized to ``\n``), so it is the same on every
## machine and checkout. Files and directories whose names start with a dot (like
## ``.git``) are not part of the data.
##
## Limitation: ``std/json`` keeps the last of two equal keys of an object without
## complaint, so duplicate keys are not detected.

import std/[json, options, os, strutils, tables, algorithm, sequtils, streams]
import ../shopbits, date, jsoncheck, sha256, tax_nexus

export tax_nexus  # a Snapshot has a NexusRegistry
export jsoncheck.Issue, jsoncheck.`$`

const SchemaVersion* = 1
  ## The version of the file layout and formats described above.

type
  LoadIssue* = Issue
    ## One problem with the data.

  LoadError* = object of CatchableError
    ## Raised by `loadSnapshot`; `issues` has all the problems that were found.
    issues*: seq[LoadIssue]

  Snapshot* = object
    ## The reference data, as loaded. Do not modify it: load a new one instead.
    id*: string
      ## derived from the content of the files, see the module docs
    name*: string  ## from the manifest, may be empty
    files*: seq[string]  ## the files the data was loaded from, sorted
    nexuses*: NexusRegistry

func shortId*(snapshot: Snapshot): string =
  ## The first 12 characters of the id, enough to tell snapshots apart.
  snapshot.id[0 ..< min(12, snapshot.id.len)]

func ruleCount*(snapshot: Snapshot): int =
  for nexus in snapshot.nexuses:
    result += nexus.rules.len

func tryParseRate(s: string): Option[Decimal] =
  ## A rate between 0 and 1 written as digits, a point and 1 to 6 digits.
  let parts = s.split('.')
  if parts.len != 2: return none(Decimal)
  let (whole, fraction) = (parts[0], parts[1])
  if whole notin ["0", "1"] or fraction.len notin 1 .. 6: return none(Decimal)
  for c in fraction:
    if c notin {'0'..'9'}: return none(Decimal)
  if whole == "1" and fraction.strip(chars = {'0'}).len > 0: return none(Decimal)
  some(newDecimal(s))

# ---------------------------------------------------------------------------
# the files

const
  businessTypeNames = [("b2c", btB2C), ("b2b", btB2B)]
  goodsTypeNames = [("physical", GoodsType.physical), ("software", GoodsType.software),
                    ("book", GoodsType.book)]

proc parseRule(node: JsonNode, file, where: string,
               issues: var seq[LoadIssue]): Option[TaxRule] =
  if node.kind != JObject:
    problem(issues, file, where, "must be an object, not " & describe(node.kind))
    return none(TaxRule)
  let before = issues.len
  checkFields(node, ["tax", "destination", "goodsTypes", "businessTypes", "rate",
                     "treatment", "reason", "validFrom", "validUntil"], file, where, issues)
  var rule = TaxRule(goodsTypes: AllGoodsTypes, businessTypes: AllBusinessTypes,
                     treatment: TaxTreatment.standard)
  rule.tax = stringField(node, "tax", false, file, where, issues).get(DefaultTax)
  let destination = stringField(node, "destination", true, file, where, issues)
  if destination.isSome: rule.destination = destination.get
  rule.goodsTypes = setField(node, "goodsTypes", goodsTypeNames, file, where,
                             issues).get(AllGoodsTypes)
  rule.businessTypes = setField(node, "businessTypes", businessTypeNames, file, where,
                                issues).get(AllBusinessTypes)
  let rate = stringField(node, "rate", true, file, where, issues)
  if rate.isSome:
    let parsed = tryParseRate(rate.get)
    if parsed.isNone:
      problem(issues, file, where.at("rate"), "'" & rate.get &
              "' is not a rate (digits, a point and up to 6 digits, between 0 and 1, " &
              "as a string like \"0.19\")")
    else:
      rule.rate = parsed.get
  rule.treatment = enumField[TaxTreatment](node, "treatment", false, file, where,
                                           issues).get(TaxTreatment.standard)
  rule.reason = stringField(node, "reason", false, file, where, issues).get("")
  rule.validFrom = dateField(node, "validFrom", file, where, issues)
  rule.validUntil = dateField(node, "validUntil", file, where, issues)
  if rule.validFrom.isSome and rule.validUntil.isSome and
      rule.validUntil.get < rule.validFrom.get:
    problem(issues, file, where, "validFrom (" & $rule.validFrom.get &
            ") is after validUntil (" & $rule.validUntil.get & ")")
  if issues.len == before: some(rule) else: none(TaxRule)

proc parseNexus(node: JsonNode, file: string,
                issues: var seq[LoadIssue]): Option[Nexus] =
  if node.kind != JObject:
    problem(issues, file, "", "must be an object, not " & describe(node.kind))
    return none(Nexus)
  let before = issues.len
  checkFields(node, ["seller", "source", "fallback", "rules"], file, "", issues)
  var nexus: Nexus
  let seller = stringField(node, "seller", true, file, "", issues)
  if seller.isSome: nexus.seller = seller.get
  let source = stringField(node, "source", true, file, "", issues)
  if source.isSome: nexus.source = source.get
  let fallback = enumField[Fallback](node, "fallback", true, file, "", issues)
  if fallback.isSome: nexus.fallback = fallback.get
  if not node.hasKey("rules"):
    problem(issues, file, "rules", "required, but missing")
  elif node["rules"].kind != JArray:
    problem(issues, file, "rules", "must be an array, not " & describe(node["rules"].kind))
  else:
    for i, ruleNode in node["rules"].elems:
      let rule = parseRule(ruleNode, file, "rules[" & $i & "]", issues)
      if rule.isSome: nexus.rules.add rule.get
  if issues.len == before: some(nexus) else: none(Nexus)

proc parseManifest(node: JsonNode, file: string, issues: var seq[LoadIssue]): string =
  ## Checks the manifest and returns the name.
  if node.kind != JObject:
    problem(issues, file, "", "must be an object, not " & describe(node.kind))
    return
  checkFields(node, ["schema", "name"], file, "", issues)
  if not node.hasKey("schema"):
    problem(issues, file, "schema", "required, but missing")
  elif node["schema"].kind != JInt:
    problem(issues, file, "schema",
            "must be an integer, not " & describe(node["schema"].kind))
  elif node["schema"].getInt != SchemaVersion:
    problem(issues, file, "schema", "is " & $node["schema"].getInt &
            ", but this version reads schema " & $SchemaVersion)
  result = stringField(node, "name", false, file, "", issues).get("")

# ---------------------------------------------------------------------------
# loading

proc dataFiles(dir: string, prefix = ""): seq[string] =
  ## All files below `dir`, relative, with ``/`` as separator and sorted;
  ## names starting with a dot are skipped.
  for kind, path in walkDir(dir, relative = true):
    if path.startsWith("."): continue
    case kind
    of pcFile, pcLinkToFile:
      result.add prefix & path
    of pcDir, pcLinkToDir:
      result.add dataFiles(dir / path, prefix & path & "/")
  result.sort()

func normalizeNewlines(content: string): string =
  content.replace("\r\n", "\n")

proc parseFile(contents: Table[string, string], file: string,
               issues: var seq[LoadIssue]): Option[JsonNode] =
  ## The parsed JSON of a file that was read; a syntax error is an issue.
  if file notin contents: return none(JsonNode)
  try:
    some(parseJson(newStringStream(contents[file]), file))
  except JsonParsingError:
    problem(issues, file, "", "is not valid JSON: " & getCurrentExceptionMsg())
    none(JsonNode)

proc loadInto(dir: string, issues: var seq[LoadIssue]): Snapshot =
  if not dirExists(dir):
    problem(issues, "", "", "the data directory '" & dir & "' does not exist")
    return
  let files = dataFiles(dir)
  result.files = files

  # read everything once; the id is derived from exactly what is parsed
  var contents: Table[string, string]
  var hashed = ""
  for file in files:
    try:
      let content = normalizeNewlines(readFile(dir / file))
      contents[file] = content
      hashed.add file & "\0" & $content.len & "\0" & content & "\n"
    except IOError, OSError:
      problem(issues, file, "", "cannot be read: " & getCurrentExceptionMsg())
  result.id = sha256Hex(hashed)

  # the layout: only the manifest and nexuses/*.json
  var nexusFiles: seq[string]
  for file in files:
    if file == "manifest.json": discard
    elif file.startsWith("nexuses/") and file.count('/') == 1 and file.endsWith(".json"):
      nexusFiles.add file
    else:
      problem(issues, file, "",
              "unexpected file (the data directory has manifest.json and nexuses/*.json)")

  if "manifest.json" notin files:
    problem(issues, "manifest.json", "", "missing")
  else:
    let manifest = parseFile(contents, "manifest.json", issues)
    if manifest.isSome:
      result.name = parseManifest(manifest.get, "manifest.json", issues)

  var defined: Table[(string, string), string]  # (seller, source) -> file
  for file in nexusFiles:
    let node = parseFile(contents, file, issues)
    if node.isNone: continue
    let nexus = parseNexus(node.get, file, issues)
    if nexus.isNone: continue
    let key = (nexus.get.seller, nexus.get.source)
    if key in defined:
      problem(issues, file, "", "there already is a nexus for seller '" &
              nexus.get.seller & "' delivering from '" & nexus.get.source &
              "', in " & defined[key])
    else:
      defined[key] = file
      result.nexuses.add nexus.get

proc checkSnapshot*(dir: string): seq[LoadIssue] =
  ## All the problems with the data in `dir`; none means it can be loaded.
  discard loadInto(dir, result)

proc loadSnapshot*(dir: string): Snapshot =
  ## Load and validate the data in `dir`. Raises `LoadError` if there is anything
  ## wrong with it; the error has all the problems.
  var issues: seq[LoadIssue]
  result = loadInto(dir, issues)
  if issues.len > 0:
    var e = newException(LoadError, $issues.len & " problem(s) in the data in '" &
                         dir & "':\n" & issues.mapIt($it).join("\n"))
    e.issues = issues
    raise e
