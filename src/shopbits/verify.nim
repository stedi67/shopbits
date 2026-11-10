## Verifying a cart: which taxes apply to it, and what it costs.
##
## `verify` takes a request (JSON), applies the tax rules of a `Snapshot` to every
## line and returns the result (JSON). The result says which snapshot it was
## computed from (its id) and for which day, so that it can be reproduced.
##
## Request:
##
## ::
##   {
##     "asOf": "2026-06-15",
##     "buyer": {"country": "gb", "businessType": "b2c"},
##     "seller": "acme",
##     "deliverySource": "de",
##     "lines": [
##       {"id": "sku-1", "goodsType": "physical", "quantity": 2,
##        "price": {"amount": "100.00", "currency": "EUR", "type": "net"}},
##       {"id": "sku-2", "goodsType": "book", "quantity": 1, "seller": "globex",
##        "deliverySource": "us",
##        "price": {"amount": "20.00", "currency": "USD", "type": "gross"}}
##     ]
##   }
##
## * ``asOf`` (``YYYY-MM-DD``): the day the sale is for, selects the rules that are
##   effective then. There is no default.
## * ``buyer``: ``country`` and ``businessType`` (``b2c`` or ``b2b``) are required;
##   ``region`` and ``postalCode`` are optional.
## * ``seller`` and ``deliverySource`` (the tax region the goods are delivered from)
##   are the defaults for all the lines, and a line can have its own.
## * a line has an ``id``, a ``goodsType`` (``physical``, ``software`` or ``book``), a
##   ``quantity`` (1 to 100000), a ``price`` of one article and optionally a
##   ``name``. A price has an ``amount`` (a string with a decimal point and 1 to 4
##   decimals, up to 9 digits before it), a ``currency`` (``EUR`` or ``USD``) and a
##   ``type`` (``net``: the taxes are added; ``gross``: the taxes are contained).
## * ``format`` (optional): must be 1.
##
## The request is checked strictly: unknown fields, wrong types and bad values are
## errors, and all of them are reported together, each with its position.
##
## Response:
##
## ::
##   {
##     "format": 1, "snapshot": "5c1952...", "asOf": "2026-06-15", "allowed": true,
##     "lines": [
##       {"index": 0, "id": "sku-1", "quantity": 2, "allowed": true,
##        "price": {"amount": "100.00", "currency": "EUR", "type": "net"},
##        "taxes": [{"tax": "vat", "rate": "0.19", "treatment": "standard",
##                   "amount": "38.00"}],
##        "net": "200.00", "tax": "38.00", "gross": "238.00"},
##       {"index": 1, "id": "sku-2", "quantity": 1, "allowed": false,
##        "reason": "seller 'globex' ... may not sell to ..."}
##     ],
##     "totals": [{"currency": "EUR", "net": "200.00", "tax": "38.00", "gross": "238.00"}]
##   }
##
## * The amounts of a line (``net``, ``tax``, ``gross`` and the ``amount`` of each tax)
##   are for the **whole line**: the taxes are computed on the price times the
##   quantity, not per article, so that rounding does not add up over the articles.
##   Amounts are strings, never numbers.
## * A line the seller may not sell is not an error: it has ``"allowed": false`` and
##   a ``reason``, and the response has ``"allowed": false``. It is not part of the
##   totals.
## * ``taxes`` is empty, and the line has a ``note``, if no rule applies but the
##   seller sells without tax. A tax has a ``reason`` if its rule has one.
## * ``totals`` has one entry for each currency, over the allowed lines.
##
## A malformed request does not get such a result: `verify` returns ``ok`` false
## and a body with the ``errors`` (each with a ``where`` and a ``message``).

import std/[json, options, strutils, tables, algorithm]
import ../shopbits, date, jsoncheck, snapshot, tax_nexus

export jsoncheck.Issue

const
  FormatVersion* = 1
    ## The version of the request and response format.
  MaxLines* = 1000
  MaxQuantity* = 100_000
  MaxLineValue = 1_000_000_000_000'i64
    ## The most that the total of a line (price times quantity) may be, in the
    ## smallest unit of its price; this keeps the arithmetic within 64 bits.

type
  CartLine* = object
    id*: string
    name*: string
    goodsType*: GoodsType
    quantity*: int
    price*: CatalogPrice  ## the price of one article
    seller*: string
    deliverySource*: string

  Cart* = object
    asOf*: Date
    buyer*: TaxAddress
    businessType*: BusinessType
    lines*: seq[CartLine]

  VerifyResponse* = object
    ok*: bool
      ## false if the request is malformed: `body` then has the errors
    body*: JsonNode

# ---------------------------------------------------------------------------
# reading the request

func tryParseAmount(s: string): Option[Decimal] =
  ## Digits, a point and 1 to 4 digits; at most 9 digits before the point.
  let parts = s.split('.')
  if parts.len != 2: return none(Decimal)
  let (whole, fraction) = (parts[0], parts[1])
  if whole.len notin 1 .. 9 or fraction.len notin 1 .. 4: return none(Decimal)
  for c in whole & fraction:
    if c notin {'0'..'9'}: return none(Decimal)
  some((value: int64(parseBiggestInt(whole & fraction)), prec: int8(fraction.len)))

proc intField(node: JsonNode, key: string, low, high: int, where: string,
              issues: var seq[Issue]): Option[int] =
  let position = where.at(key)
  if not node.hasKey(key):
    problem(issues, "", position, "required, but missing")
  elif node[key].kind != JInt:
    problem(issues, "", position, "must be an integer, not " & describe(node[key].kind))
  elif node[key].getInt notin low .. high:
    problem(issues, "", position, "must be between " & $low & " and " & $high)
  else:
    return some(node[key].getInt)
  none(int)

proc objectField(node: JsonNode, key: string, where: string,
                 issues: var seq[Issue]): Option[JsonNode] =
  let position = where.at(key)
  if not node.hasKey(key):
    problem(issues, "", position, "required, but missing")
  elif node[key].kind != JObject:
    problem(issues, "", position, "must be an object, not " & describe(node[key].kind))
  else:
    return some(node[key])
  none(JsonNode)

proc parsePrice(node: JsonNode, where: string,
                issues: var seq[Issue]): Option[CatalogPrice] =
  let before = issues.len
  checkFields(node, ["amount", "currency", "type"], "", where, issues)
  var amount: Decimal
  let text = stringField(node, "amount", true, "", where, issues)
  if text.isSome:
    let parsed = tryParseAmount(text.get)
    if parsed.isNone:
      problem(issues, "", where.at("amount"), "'" & text.get & "' is not an amount " &
              "(a string with a decimal point and 1 to 4 decimals, like \"100.00\")")
    else:
      amount = parsed.get
  let currency = enumField[Currency](node, "currency", true, "", where, issues)
  let priceType = enumField[PriceType](node, "type", true, "", where, issues)
  if issues.len > before: return none(CatalogPrice)
  some(((amount, currency.get), priceType.get))

proc parseLine(node: JsonNode, where: string, defaultSeller, defaultSource: string,
               issues: var seq[Issue]): Option[CartLine] =
  if node.kind != JObject:
    problem(issues, "", where, "must be an object, not " & describe(node.kind))
    return none(CartLine)
  let before = issues.len
  checkFields(node, ["id", "name", "goodsType", "quantity", "price", "seller",
                     "deliverySource"], "", where, issues)
  var line: CartLine
  let id = stringField(node, "id", true, "", where, issues)
  if id.isSome: line.id = id.get
  line.name = stringField(node, "name", false, "", where, issues).get("")
  let goods = enumField[GoodsType](node, "goodsType", true, "", where, issues)
  if goods.isSome: line.goodsType = goods.get
  let quantity = intField(node, "quantity", 1, MaxQuantity, where, issues)
  if quantity.isSome: line.quantity = quantity.get
  let price = objectField(node, "price", where, issues)
  if price.isSome:
    let parsed = parsePrice(price.get, where.at("price"), issues)
    if parsed.isSome:
      line.price = parsed.get
      if quantity.isSome and
          int64(line.quantity) * line.price.raw.amount.value > MaxLineValue:
        problem(issues, "", where.at("price").at("amount"),
                "the total of the line (price times quantity) is too large")
  line.seller = stringField(node, "seller", false, "", where, issues).get(defaultSeller)
  if line.seller.len == 0 and not node.hasKey("seller"):
    problem(issues, "", where.at("seller"),
            "required (or give a seller for the whole request)")
  line.deliverySource = stringField(node, "deliverySource", false, "", where,
                                    issues).get(defaultSource)
  if line.deliverySource.len == 0 and not node.hasKey("deliverySource"):
    problem(issues, "", where.at("deliverySource"),
            "required (or give a deliverySource for the whole request)")
  if issues.len == before: some(line) else: none(CartLine)

proc parseCart*(node: JsonNode, issues: var seq[Issue]): Option[Cart] =
  ## Read a request. Everything that is wrong with it is added to `issues`.
  if node.kind != JObject:
    problem(issues, "", "", "the request must be an object, not " & describe(node.kind))
    return none(Cart)
  let before = issues.len
  checkFields(node, ["format", "asOf", "buyer", "seller", "deliverySource", "lines"],
              "", "", issues)
  var cart: Cart
  if node.hasKey("format"):
    if node["format"].kind != JInt or node["format"].getInt != FormatVersion:
      problem(issues, "", "format", "must be " & $FormatVersion)
  if not node.hasKey("asOf"):
    problem(issues, "", "asOf", "required, but missing")
  else:
    let day = dateField(node, "asOf", "", "", issues)
    if day.isSome: cart.asOf = day.get
  let buyer = objectField(node, "buyer", "", issues)
  if buyer.isSome:
    checkFields(buyer.get, ["country", "region", "postalCode", "businessType"],
                "", "buyer", issues)
    let country = stringField(buyer.get, "country", true, "", "buyer", issues)
    if country.isSome: cart.buyer.country_code = country.get
    cart.buyer.region = stringField(buyer.get, "region", false, "", "buyer", issues).get("")
    cart.buyer.postal_code = stringField(buyer.get, "postalCode", false, "", "buyer",
                                         issues).get("")
    let business = stringField(buyer.get, "businessType", true, "", "buyer", issues)
    if business.isSome:
      case business.get
      of "b2c": cart.businessType = btB2C
      of "b2b": cart.businessType = btB2B
      else:
        problem(issues, "", "buyer.businessType",
                "'" & business.get & "' is not valid (expected one of: b2c, b2b)")
  let defaultSeller = stringField(node, "seller", false, "", "", issues).get("")
  let defaultSource = stringField(node, "deliverySource", false, "", "", issues).get("")
  if not node.hasKey("lines"):
    problem(issues, "", "lines", "required, but missing")
  elif node["lines"].kind != JArray:
    problem(issues, "", "lines", "must be an array, not " & describe(node["lines"].kind))
  elif node["lines"].len == 0:
    problem(issues, "", "lines", "must not be empty")
  elif node["lines"].len > MaxLines:
    problem(issues, "", "lines", "must have at most " & $MaxLines & " lines")
  else:
    for i, lineNode in node["lines"].elems:
      let line = parseLine(lineNode, "lines[" & $i & "]", defaultSeller, defaultSource,
                           issues)
      if line.isSome: cart.lines.add line.get
  if issues.len == before: some(cart) else: none(Cart)

# ---------------------------------------------------------------------------
# the result

func amountText(money: Money): string = $money.amount

proc taxJson(line: TaxLine, amount: Money): JsonNode =
  result = newJObject()
  result["tax"] = %line.tax
  result["rate"] = %($line.rate)
  result["treatment"] = %($line.treatment)
  if line.reason.len > 0: result["reason"] = %line.reason
  result["amount"] = %amountText(amount)

proc priceJson(price: CatalogPrice): JsonNode =
  %*{"amount": $price.raw.amount, "currency": $price.raw.currency,
     "type": $price.priceType}

type Totals = tuple[net, tax, gross: Money]

proc verifyCart*(snapshot: Snapshot, cart: Cart): JsonNode =
  ## The result for a valid cart.
  var
    lines = newJArray()
    totals: Table[string, Totals]
    everythingAllowed = true
  for index, line in cart.lines:
    var entry = newJObject()
    entry["index"] = %index
    entry["id"] = %line.id
    if line.name.len > 0: entry["name"] = %line.name
    entry["quantity"] = %line.quantity
    let lookup = snapshot.nexuses.taxFor(line.seller, line.deliverySource, cart.buyer,
                                         cart.businessType, line.goodsType, cart.asOf)
    if not lookup.allowed:
      everythingAllowed = false
      entry["allowed"] = %false
      entry["reason"] = %lookup.reason
      lines.add entry
      continue
    # the taxes are computed on the whole line, not on one article
    let unit = line.price
    let totalAmount: Decimal = (value: int64(line.quantity) * unit.raw.amount.value,
                                prec: unit.raw.amount.prec)
    let total: CatalogPrice = ((totalAmount, unit.raw.currency), unit.priceType)
    let priced = total.withTax(lookup.decision.lines)
    let amounts = priced.taxAmounts
    var taxes = newJArray()
    for i, taxLine in lookup.decision.lines:
      taxes.add taxJson(taxLine, amounts[i])
    entry["allowed"] = %true
    entry["price"] = priceJson(unit)
    entry["taxes"] = taxes
    entry["net"] = %amountText(priced.net)
    entry["tax"] = %amountText(priced.tax)
    entry["gross"] = %amountText(priced.gross)
    if lookup.decision.reason.len > 0: entry["note"] = %lookup.decision.reason
    lines.add entry
    let currency = $unit.raw.currency
    if currency notin totals:
      totals[currency] = (priced.net, priced.tax, priced.gross)
    else:
      let sum = totals[currency]
      totals[currency] = (sum.net + priced.net, sum.tax + priced.tax,
                          sum.gross + priced.gross)
  var totalsJson = newJArray()
  var currencies: seq[string]
  for currency in totals.keys: currencies.add currency
  currencies.sort()
  for currency in currencies:
    let sum = totals[currency]
    totalsJson.add %*{"currency": currency, "net": amountText(sum.net),
                      "tax": amountText(sum.tax), "gross": amountText(sum.gross)}
  result = %*{"format": FormatVersion, "snapshot": snapshot.id, "asOf": $cart.asOf,
              "allowed": everythingAllowed, "lines": lines, "totals": totalsJson}

# ---------------------------------------------------------------------------
# the entry points

proc errorBody(issues: seq[Issue]): JsonNode =
  var errors = newJArray()
  for issue in issues:
    errors.add %*{"where": issue.where, "message": issue.message}
  %*{"format": FormatVersion, "errors": errors}

proc verify*(snapshot: Snapshot, request: JsonNode): VerifyResponse =
  ## Verify a cart, given as parsed JSON. A malformed request gives ``ok`` false and
  ## all its errors in the body.
  var issues: seq[Issue]
  let cart = parseCart(request, issues)
  if cart.isNone:
    return VerifyResponse(ok: false, body: errorBody(issues))
  VerifyResponse(ok: true, body: verifyCart(snapshot, cart.get))

proc verifyText*(snapshot: Snapshot, request: string): VerifyResponse =
  ## Like `verify`, for a request that is not parsed yet.
  var node: JsonNode
  try:
    node = parseJson(request)
  except JsonParsingError:
    return VerifyResponse(ok: false, body: errorBody(@[Issue(
      message: "the request is not valid JSON: " & getCurrentExceptionMsg())]))
  snapshot.verify(node)
