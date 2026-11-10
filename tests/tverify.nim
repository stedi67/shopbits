import std/[unittest, json, os, strutils, sequtils, algorithm, options]
import shopbits
import shopbits/[snapshot, verify]

let
  exampleData = currentSourcePath().parentDir.parentDir / "examples" / "data"
  data = loadSnapshot(exampleData)

func line(id = "sku-1", goods = "physical", quantity = 1, amount = "100.00",
          currency = "EUR", kind = "net", extra = ""): string =
  ## A line of a request.
  """{"id": "$1", "goodsType": "$2", "quantity": $3,
      "price": {"amount": "$4", "currency": "$5", "type": "$6"}$7}""" %
    [id, goods, $quantity, amount, currency, kind, extra]

func request(lines: string, seller = "acme", source = "de", country = "de",
             day = "2026-06-15", business = "b2c"): string =
  ## A request with the seller and delivery source as defaults for the lines.
  """{"asOf": "$1", "buyer": {"country": "$2", "businessType": "$3"},
      "seller": "$4", "deliverySource": "$5", "lines": [$6]}""" %
    [day, country, business, seller, source, lines]

proc ask(request: string): JsonNode =
  ## The result for a request that is fine.
  let response = data.verifyText(request)
  doAssert response.ok, "the request was refused: " & $response.body
  response.body

proc mistakes(request: string): seq[string] =
  ## "where: message" for each error of a request that is malformed.
  let response = data.verifyText(request)
  doAssert not response.ok, "the request was accepted: " & $response.body
  for error in response.body["errors"].elems:
    result.add error["where"].getStr & ": " & error["message"].getStr

proc wheres(request: string): seq[string] =
  for error in data.verifyText(request).body["errors"].elems:
    result.add error["where"].getStr

func taxAmounts(entry: JsonNode): seq[string] =
  for tax in entry["taxes"].elems: result.add tax["amount"].getStr

suite "a result":
  test "a domestic sale, with all the fields":
    let body = ask(request(line(extra = """, "name": "a mug" """), source = "gb", country = "gb"))
    check body["format"].getInt == 1
    check body["snapshot"].getStr == data.id
    check body["asOf"].getStr == "2026-06-15"
    check body["allowed"].getBool
    let entry = body["lines"][0]
    check entry["index"].getInt == 0
    check entry["id"].getStr == "sku-1"
    check entry["name"].getStr == "a mug"
    check entry["quantity"].getInt == 1
    check entry["allowed"].getBool
    check entry["price"] == %*{"amount": "100.00", "currency": "EUR", "type": "net"}
    check entry["taxes"].len == 1
    check entry["taxes"][0]["tax"].getStr == "vat"
    check entry["taxes"][0]["rate"].getStr == "0.20"
    check entry["taxes"][0]["treatment"].getStr == "standard"
    check entry["taxes"][0]["amount"].getStr == "20.00"
    check not entry["taxes"][0].hasKey("reason")
    check entry["net"].getStr == "100.00"
    check entry["tax"].getStr == "20.00"
    check entry["gross"].getStr == "120.00"
    check not entry.hasKey("note")
    check body["totals"] == %*[{"currency": "EUR", "net": "100.00", "tax": "20.00", "gross": "120.00"}]

  test "amounts are strings, never numbers":
    let body = ask(request(line()))
    let entry = body["lines"][0]
    for key in ["net", "tax", "gross"]:
      check entry[key].kind == JString
    for tax in entry["taxes"].elems:
      check tax["rate"].kind == JString
      check tax["amount"].kind == JString
    for total in body["totals"].elems:
      for key in ["net", "tax", "gross"]:
        check total[key].kind == JString

  test "several taxes, in the order of the rules":
    let entry = ask(request(line()))["lines"][0]
    check entry["taxes"].len == 2
    check entry["taxes"][0]["tax"].getStr == "vat"
    check entry["taxes"][0]["rate"].getStr == "0.19"
    check entry["taxes"][1]["tax"].getStr == "levy"
    check entry["taxes"][1]["rate"].getStr == "0.02"
    check entry.taxAmounts == @["19.00", "2.00"]
    check entry["tax"].getStr == "21.00"
    check entry["gross"].getStr == "121.00"

  test "the day decides which rule applies":
    let before = ask(request(line(), day = "2026-12-31"))["lines"][0]
    check before["taxes"][0]["rate"].getStr == "0.19"
    let after = ask(request(line(), day = "2027-01-01"))["lines"][0]
    check after["taxes"][0]["rate"].getStr == "0.21"
    check after.taxAmounts == @["21.00", "2.00"]
    check after["gross"].getStr == "123.00"
    check ask(request(line(), day = "2027-01-01"))["asOf"].getStr == "2027-01-01"

  test "goods have their own rates, and only the taxes that apply":
    let entry = ask(request(line(goods = "book")))["lines"][0]
    check entry["taxes"].len == 1  # no levy on books
    check entry["taxes"][0]["rate"].getStr == "0.07"
    check entry["tax"].getStr == "7.00"

  test "the taxes are computed on the whole line, not on one article":
    # 3 * 0.33 = 0.99; 20% of it is 0.198 -> 0.20. Per article it would be 0.066 -> 0.07
    # each, 0.21 for three.
    let entry = ask(request(line(quantity = 3, amount = "0.33"), source = "gb",
                            country = "gb"))["lines"][0]
    check entry["quantity"].getInt == 3
    check entry["price"]["amount"].getStr == "0.33"  # the price of one article
    check entry["net"].getStr == "0.99"
    check entry["tax"].getStr == "0.20"
    check entry["gross"].getStr == "1.19"

  test "a gross price contains the taxes":
    let entry = ask(request(line(amount = "121.00", kind = "gross")))["lines"][0]
    check entry.taxAmounts == @["19.00", "2.00"]
    check entry["net"].getStr == "100.00"
    check entry["tax"].getStr == "21.00"
    check entry["gross"].getStr == "121.00"
    check entry["price"]["type"].getStr == "gross"

  test "a gross price gives the tax that is contained in it, to the cent":
    # 100.00 gross at 20%: 100 * 0.20 / 1.20 = 16.67
    let entry = ask(request(line(amount = "100.00", kind = "gross"), source = "gb",
                             country = "gb"))["lines"][0]
    check entry["tax"].getStr == "16.67"
    check entry["net"].getStr == "83.33"
    check entry["gross"].getStr == "100.00"

  test "import tax payable by the customer, with its reason":
    let entry = ask(request(line(), source = "de", country = "gb"))["lines"][0]
    check entry["allowed"].getBool
    check entry["taxes"][0]["treatment"].getStr == "importDueByCustomer"
    check entry["taxes"][0]["rate"].getStr == "0.00"
    check entry["taxes"][0]["amount"].getStr == "0.00"
    check "import tax" in entry["taxes"][0]["reason"].getStr
    check entry["gross"].getStr == entry["net"].getStr
    # the same buyer, delivered from a warehouse in the same country: a domestic sale
    let domestic = ask(request(line(), source = "gb", country = "gb"))["lines"][0]
    check domestic["taxes"][0]["treatment"].getStr == "standard"
    check domestic["tax"].getStr == "20.00"

  test "a seller that sells worldwide, without tax where it has no rule":
    let body = ask(request(line(), seller = "globex", source = "us", country = "jp"))
    let entry = body["lines"][0]
    check entry["allowed"].getBool
    check entry["taxes"].len == 0
    check entry["tax"].getStr == "0.00"
    check entry["gross"].getStr == "100.00"
    check "'jp'" in entry["note"].getStr
    check "2026-06-15" in entry["note"].getStr
    check body["totals"][0]["tax"].getStr == "0.00"

  test "a line that may not be sold is not an error, and is not in the totals":
    let body = ask(request(line("a") & "," & line("b", amount = "50.00"),
                           country = "jp"))  # acme in de has no rule for jp
    check not body["allowed"].getBool
    for entry in body["lines"].elems:
      check not entry["allowed"].getBool
      check "'jp'" in entry["reason"].getStr
      check "acme" in entry["reason"].getStr
      check not entry.hasKey("taxes")
      check not entry.hasKey("gross")
    check body["totals"].len == 0

  test "one line that is not allowed does not spoil the others":
    let lines = line("fine") & "," & line("not", extra = """, "seller": "nobody" """)
    let body = ask(request(lines))
    check not body["allowed"].getBool
    check body["lines"][0]["allowed"].getBool
    check not body["lines"][1]["allowed"].getBool
    check "no nexus" in body["lines"][1]["reason"].getStr
    # the totals only have the line that is allowed
    check body["totals"] == %*[{"currency": "EUR", "net": "100.00", "tax": "21.00", "gross": "121.00"}]

  test "lines can have their own seller and delivery source":
    let lines = line("a") & "," &
      line("b", extra = """, "seller": "acme", "deliverySource": "gb" """)
    let body = ask(request(lines, source = "de", country = "gb"))
    check body["lines"][0]["taxes"][0]["treatment"].getStr == "importDueByCustomer"
    check body["lines"][1]["taxes"][0]["treatment"].getStr == "standard"

  test "the totals have one entry for each currency, sorted":
    let lines = line("a", amount = "100.00", currency = "USD", extra =
                       """, "seller": "globex", "deliverySource": "us" """) & "," &
                line("b", amount = "10.00") & "," &
                line("c", amount = "20.00") & "," &
                line("d", amount = "5.00", currency = "USD", extra =
                       """, "seller": "globex", "deliverySource": "us" """)
    let totals = ask(request(lines, country = "de"))["totals"]
    check totals.len == 2
    check totals[0]["currency"].getStr == "EUR"
    check totals[0]["net"].getStr == "30.00"
    check totals[0]["tax"].getStr == "6.30"   # 21% of 30.00
    check totals[0]["gross"].getStr == "36.30"
    check totals[1]["currency"].getStr == "USD"
    check totals[1]["net"].getStr == "105.00"
    check totals[1]["tax"].getStr == "0.00"
    check totals[1]["gross"].getStr == "105.00"

  test "the total of the lines is the sum of the lines":
    let lines = line("a", amount = "0.99") & "," & line("b", amount = "10.01") & "," &
                line("c", amount = "33.33", quantity = 3)
    let body = ask(request(lines))
    var net, tax, gross = 0
    for entry in body["lines"].elems:
      net += parseInt(entry["net"].getStr.replace(".", ""))
      tax += parseInt(entry["tax"].getStr.replace(".", ""))
      gross += parseInt(entry["gross"].getStr.replace(".", ""))
    let total = body["totals"][0]
    check parseInt(total["net"].getStr.replace(".", "")) == net
    check parseInt(total["tax"].getStr.replace(".", "")) == tax
    check parseInt(total["gross"].getStr.replace(".", "")) == gross
    check net + tax == gross

  test "the largest line that is accepted":
    # 10000000.00 * 1000 = 1e12 units of 0.01
    let entry = ask(request(line(amount = "10000000.00", quantity = 1000)))["lines"][0]
    check entry["net"].getStr == "10000000000.00"
    check entry["tax"].getStr == "2100000000.00"

  test "the same request always gives the same result":
    let text = request(line() & "," & line("b", goods = "book", quantity = 4, amount = "12.34"))
    check $ask(text) == $ask(text)
    check ask(text)["snapshot"].getStr == data.id

  test "the result does not depend on the order of the keys of the request":
    let a = """{"asOf": "2026-06-15", "buyer": {"country": "de", "businessType": "b2c"},
                "seller": "acme", "deliverySource": "de", "lines": [""" & line() & "]}"
    let b = """{"lines": [""" & line() & """], "deliverySource": "de", "seller": "acme",
                "buyer": {"businessType": "b2c", "country": "de"}, "asOf": "2026-06-15"}"""
    check $ask(a) == $ask(b)

  test "the optional parts of the buyer":
    let text = """{"asOf": "2026-06-15", "format": 1, "seller": "acme", "deliverySource": "de",
      "buyer": {"country": "de", "region": "Berlin", "postalCode": "10407", "businessType": "b2b"},
      "lines": [""" & line() & "]}"
    check ask(text)["allowed"].getBool
    var errors: seq[Issue]
    let cart = parseCart(parseJson(text), errors)
    check errors.len == 0
    check cart.get.buyer.country_code == "de"
    check cart.get.buyer.region == "Berlin"
    check cart.get.buyer.postal_code == "10407"
    check cart.get.businessType == btB2B
    check cart.get.asOf == initDate(2026, 6, 15)
    check cart.get.lines[0].seller == "acme"
    check cart.get.lines[0].deliverySource == "de"

suite "a malformed request":
  test "it is refused with all its errors, not computed":
    let response = data.verifyText("{}")
    check not response.ok
    check response.body["format"].getInt == 1
    check response.body["errors"].len == 3
    check not response.body.hasKey("lines")
    check not response.body.hasKey("snapshot")

  test "an empty request lacks the date, the buyer and the lines":
    check wheres("{}").sorted == @["asOf", "buyer", "lines"]
    check mistakes("{}")[0].contains("required")

  test "the request must be valid JSON, and an object":
    check "not valid JSON" in mistakes("{")[0]
    check "not valid JSON" in mistakes("")[0]
    check mistakes("[]") == @[": the request must be an object, not an array"]
    check mistakes("5") == @[": the request must be an object, not an integer"]
    check mistakes("null") == @[": the request must be an object, not null"]

  test "unknown fields are errors, so that a typo is not ignored":
    let text = request(line()).replace("\"seller\"", "\"sellers\"")
    check wheres(text).sorted == @["lines[0].seller", "sellers"]  # and so the seller is missing
    let day = request(line()).replace("\"asOf\"", "\"asof\"")
    check wheres(day).sorted == @["asOf", "asof"]  # the date is missing, and asof is unknown
    check "unknown field" in mistakes(day).filterIt(it.startsWith("asof"))[0]

  test "the format, if given, must be 1":
    check wheres("""{"format": 2, "asOf": "2026-06-15"}""").contains("format")
    check wheres("""{"format": "1"}""").contains("format")

  test "the day":
    for day in ["2026-02-30", "26-01-01", "tomorrow", "2026-1-1", ""]:
      check wheres(request(line(), day = day)) == @["asOf"]
    check "string" in mistakes(request(line()).replace("\"2026-06-15\"", "20260615"))[0]

  test "the buyer":
    let text = """{"asOf": "2026-06-15", "seller": "acme", "deliverySource": "de",
                   "buyer": {}, "lines": [""" & line() & "]}"
    check wheres(text).sorted == @["buyer.businessType", "buyer.country"]
    check wheres(request(line(), business = "b2x")) == @["buyer.businessType"]
    check "b2c, b2b" in mistakes(request(line(), business = "B2C"))[0]
    check wheres(request(line()).replace("\"country\"", "\"land\"")).sorted ==
      @["buyer.country", "buyer.land"]
    check wheres("""{"asOf": "2026-06-15", "buyer": 5, "lines": []}""").contains("buyer")

  test "the lines":
    check wheres(request("")) == @["lines"]
    check "must not be empty" in mistakes(request(""))[0]
    check wheres("""{"asOf": "2026-06-15", "buyer": {"country": "de", "businessType": "b2c"},
                     "lines": {}}""") == @["lines"]
    check wheres(request("5")) == @["lines[0]"]
    let many = toSeq(1 .. 1001).mapIt(line("sku-" & $it)).join(",")
    check wheres(request(many)) == @["lines"]
    check "at most 1000" in mistakes(request(many))[0]
    # 1000 lines are fine
    check ask(request(toSeq(1 .. 1000).mapIt(line("sku-" & $it)).join(",")))["lines"].len == 1000

  test "a line needs an id, a goods type, a quantity and a price":
    check wheres(request("{}")).sorted == @["lines[0].goodsType", "lines[0].id",
                                              "lines[0].price", "lines[0].quantity"]

  test "the quantity is an integer from 1 to 100000":
    for quantity in ["0", "-1", "100001", "1.5", "\"2\"", "null", "true"]:
      let text = request(line().replace("\"quantity\": 1", "\"quantity\": " & quantity))
      check wheres(text) == @["lines[0].quantity"]
    check ask(request(line(quantity = 100000, amount = "1.00")))["lines"][0]["quantity"].getInt == 100000

  test "goods types are checked exactly":
    for goods in ["food", "Physical", "PHYSICAL", ""]:
      check wheres(request(line(goods = goods))) == @["lines[0].goodsType"]
    check "physical, software, book" in mistakes(request(line(goods = "food")))[0]

  test "amounts are strings with a decimal point and 1 to 4 decimals":
    for amount in ["100", "100.", ".5", "1e2", "100.12345", "1234567890.00", "-1.00", " 1.00",
                   "1,00", "1.0.0", "abc", "", "0x10"]:
      check wheres(request(line(amount = amount))) == @["lines[0].price.amount"]
    # a number is not enough
    let number = request(line()).replace("\"100.00\"", "100.00")
    check "string" in mistakes(number)[0]
    for amount in ["0.00", "0.01", "100.0", "100.0000", "1.5"]:
      check ask(request(line(amount = amount)))["allowed"].getBool

  test "currencies and price types are checked exactly":
    check wheres(request(line(currency = "GBP"))) == @["lines[0].price.currency"]
    check "EUR, USD" in mistakes(request(line(currency = "eur")))[0]
    check wheres(request(line(kind = "brutto"))) == @["lines[0].price.type"]
    check wheres(request(line(kind = "Net"))) == @["lines[0].price.type"]

  test "a price has an amount, a currency and a type, and nothing else":
    let text = request("""{"id": "a", "goodsType": "book", "quantity": 1, "price": {"extra": 1}}""")
    check wheres(text).sorted == @["lines[0].price.amount", "lines[0].price.currency",
                                   "lines[0].price.extra", "lines[0].price.type"]
    check wheres(request("""{"id": "a", "goodsType": "book", "quantity": 1, "price": 5}""")) ==
      @["lines[0].price"]

  test "a line that costs too much in total":
    # more than 1e12 units of 0.01
    check wheres(request(line(amount = "10000000.00", quantity = 1001))) == @["lines[0].price.amount"]
    check "too large" in mistakes(request(line(amount = "10000000.00", quantity = 1001)))[0]
    check wheres(request(line(amount = "999999999.9999", quantity = 1))) == @["lines[0].price.amount"]

  test "every line needs a seller and a delivery source, from the request or its own":
    let text = """{"asOf": "2026-06-15", "buyer": {"country": "de", "businessType": "b2c"},
                    "lines": [""" & line() & "]}"
    check wheres(text).sorted == @["lines[0].deliverySource", "lines[0].seller"]
    # a default for the request is enough for the lines that have none
    check ask(request(line() & "," & line("b", extra = """, "seller": "globex", "deliverySource": "us" """)))["lines"].len == 2

  test "an empty seller or delivery source is an error":
    check wheres(request(line(), seller = "")).contains("seller")
    check wheres(request(line(extra = """, "seller": "" """))) == @["lines[0].seller"]

  test "all the errors are reported together, each at its position":
    let text = """{"asOf": "never", "buyer": {"country": 5, "businessType": "b2x"},
                    "lines": [
                      {"id": "a", "goodsType": "food", "quantity": 0,
                       "price": {"amount": "1", "currency": "GBP", "type": "net"},
                       "seller": "acme", "deliverySource": "de"},
                      {"id": "b", "goodsType": "book", "quantity": 1,
                       "price": {"amount": "1.00", "currency": "EUR", "type": "net"}}
                    ]}"""
    check wheres(text).sorted == @["asOf", "buyer.businessType", "buyer.country",
                                   "lines[0].goodsType", "lines[0].price.amount",
                                   "lines[0].price.currency", "lines[0].quantity",
                                   "lines[1].deliverySource", "lines[1].seller"]

  test "an error says what is wrong":
    for mistake in mistakes(request(line(amount = "100"))):
      check "where" notin mistake
      check "decimal point" in mistake

  test "a refused request does not change anything":
    let before = data.id
    discard data.verifyText("{}")
    discard data.verifyText(request(line(amount = "x")))
    check data.id == before
    check $ask(request(line())) == $ask(request(line()))
