import std/[unittest, options, strutils]
import shopbits
import shopbits/tax_nexus

func address(country: string): TaxAddress = TaxAddress(country_code: country)

# the day the lookups are for, unless a test is about dates
let testDay = initDate(2026, 6, 15)

func rule(destination: string, rate: string,
          goods: set[GoodsType] = AllGoodsTypes,
          business: set[BusinessType] = AllBusinessTypes,
          treatment = TaxTreatment.standard, reason = "", tax = DefaultTax): TaxRule =
  TaxRule(tax: tax, destination: destination, goodsTypes: goods, businessTypes: business,
          rate: newDecimal(rate), treatment: treatment, reason: reason)

# A restricted seller: registered in "gb" and "de". The same seller has a
# different set of rules for goods delivered from a warehouse in each of them.
let
  fromGb = Nexus(seller: "acme", source: "gb", fallback: Fallback.reject, rules: @[
    rule("gb", "0.20"),
    rule("de", "0.00", treatment = TaxTreatment.importDueByCustomer,
         reason = "import tax is payable by the customer")])
  fromDe = Nexus(seller: "acme", source: "de", fallback: Fallback.reject, rules: @[
    rule("de", "0.19"),
    rule("gb", "0.00", treatment = TaxTreatment.importDueByCustomer,
         reason = "import tax is payable by the customer")])
  # A seller that sells worldwide, without tax where it has no rule
  worldwide = Nexus(seller: "globex", source: "us", fallback: Fallback.zeroTax, rules: @[
    rule("us", "0.07")])

suite "tax for a nexus":
  test "a domestic sale uses the domestic rate":
    let lookup = fromGb.taxFor(address("gb"), btB2C, GoodsType.physical, testDay)
    check lookup.allowed
    check lookup.decision.totalRate == newDecimal("0.20")
    check lookup.decision.lines[0].treatment == TaxTreatment.standard

  test "the same customer gets different rules from another delivery source":
    # a customer in gb, goods delivered from gb ...
    let domestic = fromGb.taxFor(address("gb"), btB2C, GoodsType.physical, testDay)
    check domestic.decision.totalRate == newDecimal("0.20")
    check domestic.decision.lines[0].treatment == TaxTreatment.standard
    # ... and delivered from de
    let crossBorder = fromDe.taxFor(address("gb"), btB2C, GoodsType.physical, testDay)
    check crossBorder.allowed
    check crossBorder.decision.totalRate == newDecimal("0.00")
    check crossBorder.decision.lines[0].treatment == TaxTreatment.importDueByCustomer
    check "import tax" in crossBorder.decision.lines[0].reason

  test "rules match the goods type and the business type":
    let nexus = Nexus(seller: "acme", source: "de", fallback: Fallback.reject, rules: @[
      rule("fr", "0.00", business = {btB2B}, treatment = TaxTreatment.reverseCharge),
      rule("fr", "0.20", goods = {GoodsType.physical}),
      rule("fr", "0.055", goods = {GoodsType.book})])
    check nexus.taxFor(address("fr"), btB2B, GoodsType.physical, testDay).decision.lines[0].treatment ==
      TaxTreatment.reverseCharge
    check nexus.taxFor(address("fr"), btB2C, GoodsType.physical, testDay).decision.totalRate ==
      newDecimal("0.20")
    check nexus.taxFor(address("fr"), btB2C, GoodsType.book, testDay).decision.totalRate ==
      newDecimal("0.055")
    # no rule for software to consumers: rejected, since this seller is restricted
    check not nexus.taxFor(address("fr"), btB2C, GoodsType.software, testDay).allowed

  test "the first matching rule wins":
    let nexus = Nexus(seller: "acme", source: "de", fallback: Fallback.reject, rules: @[
      rule("fr", "0.055", goods = {GoodsType.book}),
      rule("fr", "0.20")])
    check nexus.taxFor(address("fr"), btB2C, GoodsType.book, testDay).decision.totalRate ==
      newDecimal("0.055")
    check nexus.taxFor(address("fr"), btB2C, GoodsType.physical, testDay).decision.totalRate ==
      newDecimal("0.20")

suite "fallback":
  test "a restricted seller may not sell to other destinations":
    let lookup = fromGb.taxFor(address("us"), btB2C, GoodsType.physical, testDay)
    check not lookup.allowed
    check "'us'" in lookup.reason
    check "acme" in lookup.reason
    check "'gb'" in lookup.reason

  test "a worldwide seller sells without tax where it has no rule":
    let lookup = worldwide.taxFor(address("jp"), btB2C, GoodsType.software, testDay)
    check lookup.allowed
    check lookup.decision.lines.len == 0
    check lookup.decision.totalRate == newDecimal("0.00")
    check "'jp'" in lookup.decision.reason

  test "explicit rules win over the fallback":
    check worldwide.taxFor(address("us"), btB2C, GoodsType.physical, testDay).decision.totalRate ==
      newDecimal("0.07")

suite "registry":
  setup:
    var registry = NexusRegistry()
    registry.add fromGb
    registry.add fromDe
    registry.add worldwide

  test "a nexus is found by seller and delivery source":
    check registry.find("acme", "gb").get.source == "gb"
    check registry.find("acme", "de").get.source == "de"
    check registry.find("acme", "fr").isNone
    check registry.find("nobody", "gb").isNone

  test "the lookup uses the nexus of the seller and the delivery source":
    check registry.taxFor("acme", "gb", address("gb"), btB2C, GoodsType.physical, testDay)
      .decision.lines[0].treatment == TaxTreatment.standard
    check registry.taxFor("acme", "de", address("gb"), btB2C, GoodsType.physical, testDay)
      .decision.lines[0].treatment == TaxTreatment.importDueByCustomer
    check registry.taxFor("globex", "us", address("jp"), btB2C, GoodsType.physical, testDay).allowed

  test "selling without a nexus is not allowed":
    let lookup = registry.taxFor("acme", "fr", address("fr"), btB2C, GoodsType.physical, testDay)
    check not lookup.allowed
    check "no nexus" in lookup.reason
    check "'fr'" in lookup.reason
    check not registry.taxFor("nobody", "gb", address("gb"), btB2C, GoodsType.physical, testDay).allowed

  test "there is at most one nexus per seller and delivery source":
    expect ValueError:
      registry.add Nexus(seller: "acme", source: "gb", fallback: Fallback.zeroTax)
    # another source of the same seller is fine
    registry.add Nexus(seller: "acme", source: "fr", fallback: Fallback.zeroTax)
    check registry.find("acme", "fr").isSome

func withSource(item: LineItem, source: string): LineItem =
  result = item
  result.deliverySource = source

suite "line items":
  setup:
    var registry = NexusRegistry()
    registry.add fromGb
    registry.add fromDe
    registry.add worldwide

  func lineItem(seller, source: string, price: CatalogPrice,
                goods = GoodsType.physical, business = btB2C): LineItem =
    LineItem(price: price, businessType: business, quantity: 1, seller: seller,
             deliverySource: source,
             article: Article(id: "sku-1", name: "an article", goodsType: goods))

  let
    # catalog prices: no tax yet
    netPrice: CatalogPrice = (newMoney("100.00", curEur), PriceType.net)
    grossPrice: CatalogPrice = (newMoney("120.00", curEur), PriceType.gross)

  test "the tax of a domestic sale is added to a net price":
    let taxed = registry.applyTax(lineItem("acme", "gb", netPrice), address("gb"), testDay)
    check taxed.allowed
    check taxed.decision.lines[0].treatment == TaxTreatment.standard
    check taxed.price.totalRate == newDecimal("0.20")
    check taxed.price.net == newMoney("100.00", curEur)
    check taxed.price.tax == newMoney("20.00", curEur)
    check taxed.price.gross == newMoney("120.00", curEur)

  test "a gross price contains the tax":
    let taxed = registry.applyTax(lineItem("acme", "gb", grossPrice), address("gb"), testDay)
    check taxed.allowed
    check taxed.price.gross == newMoney("120.00", curEur)
    check taxed.price.net == newMoney("100.00", curEur)
    check taxed.price.tax == newMoney("20.00", curEur)

  test "the delivery source decides: the same item and buyer, other tax":
    let item = lineItem("acme", "de", netPrice)
    let crossBorder = registry.applyTax(item, address("gb"), testDay)
    check crossBorder.allowed
    check crossBorder.decision.lines[0].treatment == TaxTreatment.importDueByCustomer
    check crossBorder.price.tax == newMoney("0.00", curEur)
    check crossBorder.price.gross == newMoney("100.00", curEur)
    # delivered from gb instead
    let domestic = registry.applyTax(item.withSource("gb"), address("gb"), testDay)
    check domestic.price.tax == newMoney("20.00", curEur)

  test "the line item is returned unchanged":
    let item = lineItem("acme", "gb", netPrice, goods = GoodsType.book, business = btB2B)
    var reg = NexusRegistry()
    reg.add Nexus(seller: "acme", source: "gb", fallback: Fallback.reject, rules: @[
      rule("gb", "0.00", goods = {GoodsType.book}, business = {btB2B},
           treatment = TaxTreatment.zeroRated)])
    let taxed = reg.applyTax(item, address("gb"), testDay)
    check taxed.allowed
    check taxed.item == item
    check taxed.price.raw == item.price.raw
    check taxed.price.priceType == PriceType.net
    check taxed.price.totalRate == newDecimal("0.00")

  test "a sale that is not allowed says why":
    let taxed = registry.applyTax(lineItem("acme", "gb", netPrice), address("us"), testDay)
    check not taxed.allowed
    check "'us'" in taxed.reason
    let unknown = registry.applyTax(lineItem("nobody", "gb", netPrice), address("gb"), testDay)
    check not unknown.allowed
    check "no nexus" in unknown.reason

  test "a worldwide seller sells without tax":
    let taxed = registry.applyTax(lineItem("globex", "us", netPrice), address("jp"), testDay)
    check taxed.allowed
    check taxed.price.taxes.len == 0
    check taxed.price.tax == newMoney("0.00", curEur)
    check taxed.price.gross == newMoney("100.00", curEur)

  test "the lookup of a line item matches the lookup by its fields":
    let item = lineItem("acme", "gb", netPrice)
    check registry.taxFor(item, address("gb"), testDay).decision.totalRate ==
      registry.taxFor("acme", "gb", address("gb"), btB2C, GoodsType.physical, testDay).decision.totalRate

suite "several taxes":
  let
    multi = Nexus(seller: "acme", source: "de", fallback: Fallback.reject, rules: @[
      rule("de", "0.19", tax = "vat"),
      rule("de", "0.02", goods = {GoodsType.physical}, tax = "levy")])

  func rates(lookup: TaxLookup): seq[(string, string)] =
    for line in lookup.decision.lines:
      result.add (line.tax, $line.rate)

  test "every tax with a matching rule gives a line, in the order of the taxes":
    let lookup = multi.taxFor(address("de"), btB2C, GoodsType.physical, testDay)
    check lookup.allowed
    check lookup.decision.lines.len == 2
    check lookup.decision.lines[0].tax == "vat"
    check lookup.decision.lines[0].rate == newDecimal("0.19")
    check lookup.decision.lines[1].tax == "levy"
    check lookup.decision.lines[1].rate == newDecimal("0.02")
    check lookup.decision.totalRate == newDecimal("0.21")

  test "the order of the lines does not depend on which rule of a tax wins":
    let nexus = Nexus(seller: "acme", source: "de", fallback: Fallback.reject, rules: @[
      rule("de", "0.07", goods = {GoodsType.book}, tax = "vat"),
      rule("de", "0.02", tax = "levy"),
      rule("de", "0.19", tax = "vat")])
    # vat is listed first, so it comes first, whether the book or the general rule wins
    for goods in [GoodsType.book, GoodsType.physical]:
      let lookup = nexus.taxFor(address("de"), btB2C, goods, testDay)
      check lookup.decision.lines[0].tax == "vat"
      check lookup.decision.lines[1].tax == "levy"

  test "taxes without a matching rule are left out":
    # the levy is only for physical goods
    let lookup = multi.taxFor(address("de"), btB2C, GoodsType.software, testDay)
    check lookup.allowed
    check lookup.decision.lines.len == 1
    check lookup.decision.lines[0].tax == "vat"
    check lookup.decision.totalRate == newDecimal("0.19")

  test "for each tax the first matching rule wins, independent of the other taxes":
    let nexus = Nexus(seller: "acme", source: "de", fallback: Fallback.reject, rules: @[
      rule("de", "0.07", goods = {GoodsType.book}, tax = "vat"),
      rule("de", "0.02", goods = {GoodsType.physical}, tax = "levy"),
      rule("de", "0.19", tax = "vat")])
    # a book: the reduced vat rule comes first, the levy does not match
    let book = nexus.taxFor(address("de"), btB2C, GoodsType.book, testDay)
    check book.decision.lines.len == 1
    check book.decision.lines[0].rate == newDecimal("0.07")
    # other physical goods: the general vat rule, plus the levy
    let other = nexus.taxFor(address("de"), btB2C, GoodsType.physical, testDay)
    check other.decision.lines.len == 2
    check other.decision.lines[0].tax == "vat"
    check other.decision.lines[0].rate == newDecimal("0.19")
    check other.decision.lines[1].tax == "levy"

  test "a tax can be exempt for some goods while another still applies":
    let nexus = Nexus(seller: "acme", source: "de", fallback: Fallback.reject, rules: @[
      rule("de", "0.00", goods = {GoodsType.book}, treatment = TaxTreatment.exempt, tax = "vat"),
      rule("de", "0.19", tax = "vat"),
      rule("de", "0.02", tax = "levy")])
    let lookup = nexus.taxFor(address("de"), btB2C, GoodsType.book, testDay)
    check lookup.decision.lines[0].treatment == TaxTreatment.exempt
    check lookup.decision.totalRate == newDecimal("0.02")

  test "only a tax that is specific to a destination applies there":
    let nexus = Nexus(seller: "acme", source: "de", fallback: Fallback.reject, rules: @[
      rule("de", "0.19", tax = "vat"),
      rule("fr", "0.03", tax = "levy")])
    let lookup = nexus.taxFor(address("fr"), btB2C, GoodsType.physical, testDay)
    check lookup.allowed
    check lookup.decision.lines.len == 1
    check lookup.decision.lines[0].tax == "levy"

  test "a destination without any matching rule is still rejected or taxed by the fallback":
    check not multi.taxFor(address("us"), btB2C, GoodsType.physical, testDay).allowed
    let open = Nexus(seller: "acme", source: "de", fallback: Fallback.zeroTax, rules: multi.rules)
    check open.taxFor(address("us"), btB2C, GoodsType.physical, testDay).decision.lines.len == 0

  test "the default tax is used if a rule does not name one":
    check rule("de", "0.19").tax == DefaultTax
    let lookup = fromGb.taxFor(address("gb"), btB2C, GoodsType.physical, testDay)
    check lookup.decision.lines[0].tax == DefaultTax

  test "line items get all the taxes of their nexus":
    var registry = NexusRegistry()
    registry.add multi
    let item = LineItem(
      price: (newMoney("100.00", curEur), PriceType.net), businessType: btB2C, quantity: 1,
      seller: "acme", deliverySource: "de",
      article: Article(id: "sku-1", name: "an article", goodsType: GoodsType.physical))
    let taxed = registry.applyTax(item, address("de"), testDay)
    check taxed.allowed
    check taxed.price.taxes.len == 2
    let amounts = taxed.price.taxAmounts
    check amounts[0] == newMoney("19.00", curEur)
    check amounts[1] == newMoney("2.00", curEur)
    check taxed.price.tax == newMoney("21.00", curEur)
    check taxed.price.gross == newMoney("121.00", curEur)
    # a gross price contains all of them
    var grossItem = item
    grossItem.price = (newMoney("121.00", curEur), PriceType.gross)
    let taxedGross = registry.applyTax(grossItem, address("de"), testDay)
    check taxedGross.price.net == newMoney("100.00", curEur)
    check taxedGross.price.tax == newMoney("21.00", curEur)

suite "effective dates":
  func ruleBetween(rate: string, validFrom, validUntil: string, tax = DefaultTax): TaxRule =
    result = rule("de", rate, tax = tax)
    if validFrom != "": result.validFrom = some(parseDate(validFrom))
    if validUntil != "": result.validUntil = some(parseDate(validUntil))

  let
    # the rate changes at the turn of the year
    changing = Nexus(seller: "acme", source: "de", fallback: Fallback.reject, rules: @[
      ruleBetween("0.19", "", "2026-12-31"),
      ruleBetween("0.21", "2027-01-01", "")])

  func rateOn(nexus: Nexus, day: Date): string =
    let lookup = nexus.taxFor(address("de"), btB2C, GoodsType.physical, day)
    if lookup.allowed and lookup.decision.lines.len > 0: $lookup.decision.lines[0].rate
    else: "-"

  test "a rule only applies in its period, both ends included":
    check changing.rateOn(initDate(2026, 12, 30)) == "0.19"
    check changing.rateOn(initDate(2026, 12, 31)) == "0.19"  # the last day
    check changing.rateOn(initDate(2027, 1, 1)) == "0.21"    # the first day
    check changing.rateOn(initDate(2027, 1, 2)) == "0.21"

  test "open ended periods":
    check changing.rateOn(initDate(1990, 1, 1)) == "0.19"   # no validFrom
    check changing.rateOn(initDate(2099, 1, 1)) == "0.21"   # no validUntil

  test "a sale in the past is taxed with the rule that was effective then":
    check changing.rateOn(initDate(2024, 5, 1)) == "0.19"
    check changing.rateOn(initDate(2027, 5, 1)) == "0.21"

  test "no rule effective on the day means the fallback":
    let gap = Nexus(seller: "acme", source: "de", fallback: Fallback.reject, rules: @[
      ruleBetween("0.19", "2026-01-01", "2026-06-30"),
      ruleBetween("0.20", "2026-08-01", "2026-12-31")])
    check gap.rateOn(initDate(2026, 6, 30)) == "0.19"
    check gap.rateOn(initDate(2026, 8, 1)) == "0.20"
    let inGap = gap.taxFor(address("de"), btB2C, GoodsType.physical, initDate(2026, 7, 15))
    check not inGap.allowed
    check "2026-07-15" in inGap.reason
    # a worldwide seller sells without tax in the gap
    let open = Nexus(seller: "acme", source: "de", fallback: Fallback.zeroTax, rules: gap.rules)
    let free = open.taxFor(address("de"), btB2C, GoodsType.physical, initDate(2026, 7, 15))
    check free.allowed
    check free.decision.lines.len == 0
    check "2026-07-15" in free.decision.reason

  test "the period of one tax does not affect another tax":
    let nexus = Nexus(seller: "acme", source: "de", fallback: Fallback.reject, rules: @[
      ruleBetween("0.19", "", "", tax = "vat"),
      ruleBetween("0.02", "2027-01-01", "", tax = "levy")])
    check nexus.taxFor(address("de"), btB2C, GoodsType.physical, initDate(2026, 6, 1))
      .decision.lines.len == 1
    check nexus.taxFor(address("de"), btB2C, GoodsType.physical, initDate(2027, 6, 1))
      .decision.lines.len == 2

  test "a rule that is not yet effective does not shadow an effective one":
    # first match wins among the rules that are effective on the day
    let nexus = Nexus(seller: "acme", source: "de", fallback: Fallback.reject, rules: @[
      ruleBetween("0.25", "2030-01-01", ""),
      ruleBetween("0.19", "", "")])
    check nexus.rateOn(initDate(2026, 6, 1)) == "0.19"
    check nexus.rateOn(initDate(2030, 1, 1)) == "0.25"

  test "isEffectiveOn":
    let r = ruleBetween("0.19", "2026-03-01", "2026-03-31")
    check not r.isEffectiveOn(initDate(2026, 2, 28))
    check r.isEffectiveOn(initDate(2026, 3, 1))
    check r.isEffectiveOn(initDate(2026, 3, 31))
    check not r.isEffectiveOn(initDate(2026, 4, 1))
    check rule("de", "0.19").isEffectiveOn(initDate(2026, 3, 1))  # always effective

  test "the lookup of a registry and of a line item take the day, too":
    var registry = NexusRegistry()
    registry.add changing
    let item = LineItem(
      price: (newMoney("100.00", curEur), PriceType.net), businessType: btB2C, quantity: 1,
      seller: "acme", deliverySource: "de",
      article: Article(id: "sku-1", name: "an article", goodsType: GoodsType.physical))
    check registry.applyTax(item, address("de"), initDate(2026, 12, 31)).price.tax ==
      newMoney("19.00", curEur)
    check registry.applyTax(item, address("de"), initDate(2027, 1, 1)).price.tax ==
      newMoney("21.00", curEur)
    check registry.taxFor("acme", "de", address("de"), btB2C, GoodsType.physical,
                          initDate(2027, 1, 1)).decision.totalRate == newDecimal("0.21")

suite "registry access":
  test "the number of nexuses and iteration":
    var registry = NexusRegistry()
    check registry.len == 0
    registry.add fromGb
    registry.add fromDe
    check registry.len == 2
    var sources: seq[string]
    for nexus in registry: sources.add nexus.source
    check sources == @["gb", "de"]
