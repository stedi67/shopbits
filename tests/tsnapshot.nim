import std/[unittest, os, strutils, sequtils, algorithm, options, tempfiles]
import shopbits
import shopbits/snapshot

let exampleData = currentSourcePath().parentDir.parentDir / "examples" / "data"

template withData(files: openArray[(string, string)], dir, body: untyped) =
  ## Runs `body` with `dir` a temporary data directory with the given files.
  let dir = createTempDir("shopbits_test_", "")
  try:
    for (name, content) in files:
      createDir(parentDir(dir / name))
      writeFile(dir / name, content)
    body
  finally:
    removeDir(dir)

const
  manifest = """{"schema": 1}"""
  emptyNexus = """{"seller": "acme", "source": "de", "fallback": "reject", "rules": []}"""

func nexusWith(rules: string, seller = "acme", source = "de"): string =
  """{"seller": "$1", "source": "$2", "fallback": "reject", "rules": [$3]}""" %
    [seller, source, rules]

proc issuesOf(files: openArray[(string, string)]): seq[LoadIssue] =
  withData(files, dir):
    result = checkSnapshot(dir)

proc oneIssue(files: openArray[(string, string)]): LoadIssue =
  ## The single problem with the data.
  let issues = issuesOf(files)
  doAssert issues.len == 1, "expected one issue, got: " & issues.mapIt($it).join("; ")
  issues[0]

proc ruleIssue(rule: string): LoadIssue =
  ## The single problem with a rule in a nexus file.
  oneIssue({"manifest.json": manifest, "nexuses/a.json": nexusWith(rule)})

suite "the example data":
  test "it loads":
    let data = loadSnapshot(exampleData)
    check data.name == "example data (fictional)"
    check data.nexuses.len == 3
    check data.ruleCount == 8
    check data.files == @["manifest.json", "nexuses/acme-de.json", "nexuses/acme-gb.json",
                          "nexuses/globex-us.json"]
    check data.id.len == 64
    check data.shortId == data.id[0 ..< 12]
    check checkSnapshot(exampleData).len == 0

  test "the loaded rules work":
    let data = loadSnapshot(exampleData)
    let de = TaxAddress(country_code: "de")
    let gb = TaxAddress(country_code: "gb")
    let jp = TaxAddress(country_code: "jp")
    # the rate changes at the turn of the year, and the levy applies to physical goods
    let before = data.nexuses.taxFor("acme", "de", de, btB2C, GoodsType.physical,
                                     initDate(2026, 12, 31))
    check before.decision.lines.len == 2
    check before.decision.lines[0].rate == newDecimal("0.19")
    check before.decision.lines[1].rate == newDecimal("0.02")
    let after = data.nexuses.taxFor("acme", "de", de, btB2C, GoodsType.physical,
                                    initDate(2027, 1, 1))
    check after.decision.lines[0].rate == newDecimal("0.21")
    # books have a reduced rate and no levy
    let book = data.nexuses.taxFor("acme", "de", de, btB2C, GoodsType.book,
                                   initDate(2026, 6, 1))
    check book.decision.lines.len == 1
    check book.decision.lines[0].rate == newDecimal("0.07")
    # the same buyer in gb: import tax is payable by the customer, from de; domestic from gb
    check data.nexuses.taxFor("acme", "de", gb, btB2C, GoodsType.physical,
                              initDate(2026, 6, 1)).decision.lines[0].treatment ==
      TaxTreatment.importDueByCustomer
    check data.nexuses.taxFor("acme", "gb", gb, btB2C, GoodsType.physical,
                              initDate(2026, 6, 1)).decision.lines[0].rate ==
      newDecimal("0.20")
    # the restricted seller may not sell to jp, the worldwide seller may
    check not data.nexuses.taxFor("acme", "de", jp, btB2C, GoodsType.physical,
                                  initDate(2026, 6, 1)).allowed
    check data.nexuses.taxFor("globex", "us", jp, btB2C, GoodsType.physical,
                              initDate(2026, 6, 1)).allowed

suite "the snapshot id":
  const
    pinnedManifest = "{\"schema\": 1, \"name\": \"pinned\"}\n"
    pinnedNexus = "{\"seller\": \"acme\", \"source\": \"de\", \"fallback\": \"reject\", \"rules\": []}\n"

  func files(extra: openArray[(string, string)] = []): seq[(string, string)] =
    result = @{"manifest.json": pinnedManifest, "nexuses/acme-de.json": pinnedNexus}
    result.add extra

  proc idOf(files: openArray[(string, string)]): string =
    withData(files, dir):
      result = loadSnapshot(dir).id

  test "it is the SHA-256 of the names and contents of the files":
    # computed independently: sha256 over name, NUL, length, NUL, content, newline
    # for each file in the order of the names
    check idOf(files()) == "b0b406ef77f6e7cc7992bebb07dcbb1845c92d191f8ffab4598b4219a3675f84"

  test "the same data has the same id wherever it is":
    check idOf(files()) == idOf(files())
    check idOf(files()) == idOf(@{"nexuses/acme-de.json": pinnedNexus, "manifest.json": pinnedManifest})

  test "any change of the content changes the id":
    check idOf(files()) != idOf(@{"manifest.json": pinnedManifest,
                                  "nexuses/acme-de.json": pinnedNexus.replace("de", "dd")})
    check idOf(files()) != idOf(@{"manifest.json": pinnedManifest & " ",
                                  "nexuses/acme-de.json": pinnedNexus})

  test "the names of the files are part of the id":
    check idOf(files()) != idOf(@{"manifest.json": pinnedManifest,
                                  "nexuses/acme-xx.json": pinnedNexus})

  test "another file changes the id":
    check idOf(files()) != idOf(files({"nexuses/acme-gb.json": nexusWith("", "acme", "gb")}))

  test "line endings do not matter, so every checkout has the same id":
    check idOf(files()) == idOf(@{"manifest.json": pinnedManifest.replace("\n", "\r\n"),
                                  "nexuses/acme-de.json": pinnedNexus.replace("\n", "\r\n")})

  test "hidden files and directories are not part of the data":
    check idOf(files()) == idOf(files({".git/config": "[core]", ".DS_Store": "x",
                                       "nexuses/.hidden.json": "not even json"}))

suite "loading":
  test "the minimal data":
    withData({"manifest.json": manifest, "nexuses/a.json": emptyNexus}, dir):
      let data = loadSnapshot(dir)
      check data.nexuses.len == 1
      check data.name == ""
      check data.ruleCount == 0
      let nexus = data.nexuses.find("acme", "de").get
      check nexus.fallback == Fallback.reject
      check nexus.rules.len == 0

  test "no nexuses at all is fine":
    withData({"manifest.json": manifest}, dir):
      check loadSnapshot(dir).nexuses.len == 0

  test "a rule gets defaults for what is left out":
    withData({"manifest.json": manifest,
              "nexuses/a.json": nexusWith("""{"destination": "de", "rate": "0.19"}""")}, dir):
      let rule = loadSnapshot(dir).nexuses.find("acme", "de").get.rules[0]
      check rule.tax == DefaultTax
      check rule.destination == "de"
      check rule.rate == newDecimal("0.19")
      check rule.goodsTypes == AllGoodsTypes
      check rule.businessTypes == AllBusinessTypes
      check rule.treatment == TaxTreatment.standard
      check rule.reason == ""
      check rule.validFrom.isNone
      check rule.validUntil.isNone

  test "all the fields of a rule":
    let rule = """{"tax": "levy", "destination": "fr", "goodsTypes": ["book", "software"],
                   "businessTypes": ["b2b"], "rate": "0.055", "treatment": "reverseCharge",
                   "reason": "the customer pays", "validFrom": "2026-01-01",
                   "validUntil": "2026-12-31"}"""
    withData({"manifest.json": manifest, "nexuses/a.json": nexusWith(rule)}, dir):
      let r = loadSnapshot(dir).nexuses.find("acme", "de").get.rules[0]
      check r.tax == "levy"
      check r.destination == "fr"
      check r.goodsTypes == {GoodsType.book, GoodsType.software}
      check r.businessTypes == {btB2B}
      check r.rate == newDecimal("0.055")
      check r.treatment == TaxTreatment.reverseCharge
      check r.reason == "the customer pays"
      check r.validFrom.get == initDate(2026, 1, 1)
      check r.validUntil.get == initDate(2026, 12, 31)

  test "the order of the rules is kept":
    let rules = """{"destination": "a", "rate": "0.1"}, {"destination": "b", "rate": "0.2"},
                   {"destination": "c", "rate": "0.3"}"""
    withData({"manifest.json": manifest, "nexuses/a.json": nexusWith(rules)}, dir):
      let loaded = loadSnapshot(dir).nexuses.find("acme", "de").get.rules
      check loaded.mapIt(it.destination) == @["a", "b", "c"]

  test "rates at the limits":
    for rate in ["0.0", "0.00", "1.0", "1.000000", "0.000001", "0.999999"]:
      check issuesOf({"manifest.json": manifest,
                      "nexuses/a.json": nexusWith("""{"destination": "de", "rate": "$1"}""" % rate)}).len == 0

  test "loadSnapshot raises with all the problems, checkSnapshot returns them":
    let files = {"manifest.json": """{"schema": 2}""", "nexuses/a.json": "{"}
    withData(files, dir):
      check checkSnapshot(dir).len == 2
      try:
        discard loadSnapshot(dir)
        fail()
      except LoadError as e:
        check e.issues.len == 2
        check "2 problem(s)" in e.msg
        check "manifest.json: schema" in e.msg
        check "nexuses/a.json" in e.msg

  test "an issue prints with its file and position":
    check $LoadIssue(file: "a.json", where: "rules[1].rate", message: "bad") ==
      "a.json: rules[1].rate: bad"
    check $LoadIssue(file: "a.json", message: "bad") == "a.json: bad"
    check $LoadIssue(message: "bad") == "bad"

suite "problems with the directory":
  test "it does not exist":
    let issues = checkSnapshot(getTempDir() / "shopbits_no_such_directory")
    check issues.len == 1
    check "does not exist" in issues[0].message

  test "an empty directory has no manifest":
    let issue = oneIssue(newSeq[(string, string)]())
    check issue.file == "manifest.json"
    check issue.message == "missing"

  test "files that are not expected are reported, so that a typo does not hide data":
    for name in ["nexus/acme.json", "nexuses/sub/acme.json", "nexuses/readme.txt",
                 "README.md", "prices.csv"]:
      let issue = oneIssue({"manifest.json": manifest, name: "{}"})
      check issue.file == name
      check "unexpected file" in issue.message

suite "problems with the files":
  test "invalid JSON":
    let issue = oneIssue({"manifest.json": manifest, "nexuses/a.json": """{"seller": """})
    check issue.file == "nexuses/a.json"
    check "not valid JSON" in issue.message

  test "invalid JSON in the manifest":
    let issue = oneIssue({"manifest.json": "{"})
    check issue.file == "manifest.json"
    check "not valid JSON" in issue.message

  test "the manifest must say which schema it is":
    check oneIssue({"manifest.json": "{}"}).where == "schema"
    check "required" in oneIssue({"manifest.json": "{}"}).message
    let wrong = oneIssue({"manifest.json": """{"schema": 2}"""})
    check wrong.where == "schema"
    check "schema 1" in wrong.message
    check "integer" in oneIssue({"manifest.json": """{"schema": "1"}"""}).message
    check "integer" in oneIssue({"manifest.json": """{"schema": 1.0}"""}).message

  test "unknown fields in the manifest":
    let issue = oneIssue({"manifest.json": """{"schema": 1, "nmae": "x"}"""})
    check issue.where == "nmae"
    check "unknown field" in issue.message

  test "the name must be a string":
    check "string" in oneIssue({"manifest.json": """{"schema": 1, "name": 5}"""}).message

  test "a nexus file must be an object":
    let issue = oneIssue({"manifest.json": manifest, "nexuses/a.json": "[]"})
    check "object" in issue.message

  test "a nexus needs a seller, a source, a fallback and rules":
    let issues = issuesOf({"manifest.json": manifest, "nexuses/a.json": "{}"})
    check issues.mapIt(it.where).sorted == @["fallback", "rules", "seller", "source"]
    for issue in issues:
      check issue.file == "nexuses/a.json"
      check "required" in issue.message

  test "the fields of a nexus have to be of the right kind":
    let issues = issuesOf({"manifest.json": manifest, "nexuses/a.json":
      """{"seller": 5, "source": "", "fallback": "never", "rules": {}}"""})
    check issues.len == 4
    check issues.anyIt(it.where == "seller" and "string" in it.message)
    check issues.anyIt(it.where == "source" and "empty" in it.message)
    check issues.anyIt(it.where == "fallback" and "reject" in it.message and "zeroTax" in it.message)
    check issues.anyIt(it.where == "rules" and "array" in it.message)

  test "unknown fields in a nexus":
    let issue = oneIssue({"manifest.json": manifest, "nexuses/a.json":
      """{"seller": "a", "source": "b", "fallback": "reject", "rules": [], "rulez": 1}"""})
    check issue.where == "rulez"
    check "unknown field" in issue.message

  test "a rule must be an object":
    let issue = ruleIssue("5")
    check issue.where == "rules[0]"
    check "object" in issue.message

  test "a rule needs a destination and a rate":
    let issues = issuesOf({"manifest.json": manifest, "nexuses/a.json": nexusWith("{}")})
    check issues.mapIt(it.where).sorted == @["rules[0].destination", "rules[0].rate"]

  test "unknown fields in a rule":
    let issue = ruleIssue("""{"destination": "de", "rate": "0.1", "tax_rate": "0.2"}""")
    check issue.where == "rules[0].tax_rate"
    check "unknown field" in issue.message
    check "destination" in issue.message  # what is allowed is listed

  test "rates are strings of digits between 0 and 1":
    for rate in ["19%", "0,19", "1.5", "0.1234567", "-0.1", ".19", "19", "0.", "1.01",
                 "2.0", "0.1e1", " 0.19", "0.19 ", "0..1", "00.1", "abc"]:
      let issue = ruleIssue("""{"destination": "de", "rate": "$1"}""" % rate)
      check issue.where == "rules[0].rate"
      check "not a rate" in issue.message
    # a number is not enough: the rate would be a float
    let number = ruleIssue("""{"destination": "de", "rate": 0.19}""")
    check number.where == "rules[0].rate"
    check "string" in number.message

  test "treatments are checked exactly":
    let issue = ruleIssue("""{"destination": "de", "rate": "0.1", "treatment": "reverse_charge"}""")
    check issue.where == "rules[0].treatment"
    check "reverseCharge" in issue.message
    check ruleIssue("""{"destination": "de", "rate": "0.1", "treatment": "Standard"}""").where ==
      "rules[0].treatment"

  test "goods types and business types":
    let goods = ruleIssue("""{"destination": "de", "rate": "0.1", "goodsTypes": ["food"]}""")
    check goods.where == "rules[0].goodsTypes[0]"
    check "physical" in goods.message
    let mixed = issuesOf({"manifest.json": manifest, "nexuses/a.json": nexusWith(
      """{"destination": "de", "rate": "0.1", "goodsTypes": ["book", "x", "y"]}""")})
    check mixed.mapIt(it.where) == @["rules[0].goodsTypes[1]", "rules[0].goodsTypes[2]"]
    check "must not be empty" in ruleIssue(
      """{"destination": "de", "rate": "0.1", "businessTypes": []}""").message
    check "array" in ruleIssue(
      """{"destination": "de", "rate": "0.1", "businessTypes": "b2c"}""").message
    check ruleIssue("""{"destination": "de", "rate": "0.1", "businessTypes": ["B2C"]}""").where ==
      "rules[0].businessTypes[0]"
    check ruleIssue("""{"destination": "de", "rate": "0.1", "goodsTypes": [1]}""").where ==
      "rules[0].goodsTypes[0]"

  test "dates have to be real days in the format YYYY-MM-DD":
    for date in ["2026-02-30", "26-1-1", "2026/01/01", "tomorrow", "2026-13-01", "20260101"]:
      let issue = ruleIssue("""{"destination": "de", "rate": "0.1", "validFrom": "$1"}""" % date)
      check issue.where == "rules[0].validFrom"
      check "YYYY-MM-DD" in issue.message
    check ruleIssue("""{"destination": "de", "rate": "0.1", "validUntil": "2026-02-29"}""").where ==
      "rules[0].validUntil"

  test "a period must not end before it starts":
    let issue = ruleIssue("""{"destination": "de", "rate": "0.1",
                             "validFrom": "2026-06-02", "validUntil": "2026-06-01"}""")
    check issue.where == "rules[0]"
    check "after validUntil" in issue.message
    # a period of one day is fine
    check issuesOf({"manifest.json": manifest, "nexuses/a.json": nexusWith(
      """{"destination": "de", "rate": "0.1",
          "validFrom": "2026-06-01", "validUntil": "2026-06-01"}""")}).len == 0

  test "there is at most one nexus for a seller and a delivery source":
    let issue = oneIssue({"manifest.json": manifest, "nexuses/a.json": emptyNexus,
                          "nexuses/b.json": emptyNexus})
    check issue.file == "nexuses/b.json"  # the second one is the problem
    check "already is a nexus" in issue.message
    check "nexuses/a.json" in issue.message  # where the first is
    # a different source or seller is fine
    check issuesOf({"manifest.json": manifest, "nexuses/a.json": emptyNexus,
                    "nexuses/b.json": nexusWith("", "acme", "gb"),
                    "nexuses/c.json": nexusWith("", "other", "de")}).len == 0

  test "all the problems are reported together, each at its position":
    let rules = """{"destination": "de", "rate": "19%"},
                   {"destination": "de", "rate": "0.19"},
                   {"rate": "0.1", "treatment": "nope"}"""
    let issues = issuesOf({"manifest.json": """{"schema": 3}""",
                           "nexuses/a.json": nexusWith(rules),
                           "nexuses/b.json": "not json",
                           "stray.txt": "x"})
    let positions = issues.mapIt(it.file & ":" & it.where).sorted
    check positions == @["manifest.json:schema", "nexuses/a.json:rules[0].rate",
                         "nexuses/a.json:rules[2].destination",
                         "nexuses/a.json:rules[2].treatment", "nexuses/b.json:", "stray.txt:"]

  test "a file with a problem is not loaded at all":
    withData({"manifest.json": manifest,
              "nexuses/a.json": nexusWith("""{"destination": "de", "rate": "x"}"""),
              "nexuses/b.json": nexusWith("", "other", "de")}, dir):
      check checkSnapshot(dir).len == 1
      expect LoadError: discard loadSnapshot(dir)
