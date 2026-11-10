import std/[unittest, options, strutils]
import shopbits
import shopbits/tax_nexus

func address(country: string): TaxAddress = TaxAddress(country_code: country)

func rule(destination: string, rate: string,
          goods: set[GoodsType] = AllGoodsTypes,
          business: set[BusinessType] = AllBusinessTypes,
          treatment = TaxTreatment.standard, reason = ""): TaxRule =
  TaxRule(destination: destination, goodsTypes: goods, businessTypes: business,
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
    let lookup = fromGb.taxFor(address("gb"), btB2C, GoodsType.physical)
    check lookup.allowed
    check lookup.decision.rate == newDecimal("0.20")
    check lookup.decision.treatment == TaxTreatment.standard

  test "the same customer gets different rules from another delivery source":
    # a customer in gb, goods delivered from gb ...
    let domestic = fromGb.taxFor(address("gb"), btB2C, GoodsType.physical)
    check domestic.decision.rate == newDecimal("0.20")
    check domestic.decision.treatment == TaxTreatment.standard
    # ... and delivered from de
    let crossBorder = fromDe.taxFor(address("gb"), btB2C, GoodsType.physical)
    check crossBorder.allowed
    check crossBorder.decision.rate == newDecimal("0.00")
    check crossBorder.decision.treatment == TaxTreatment.importDueByCustomer
    check "import tax" in crossBorder.decision.reason

  test "rules match the goods type and the business type":
    let nexus = Nexus(seller: "acme", source: "de", fallback: Fallback.reject, rules: @[
      rule("fr", "0.00", business = {btB2B}, treatment = TaxTreatment.reverseCharge),
      rule("fr", "0.20", goods = {GoodsType.physical}),
      rule("fr", "0.055", goods = {GoodsType.book})])
    check nexus.taxFor(address("fr"), btB2B, GoodsType.physical).decision.treatment ==
      TaxTreatment.reverseCharge
    check nexus.taxFor(address("fr"), btB2C, GoodsType.physical).decision.rate ==
      newDecimal("0.20")
    check nexus.taxFor(address("fr"), btB2C, GoodsType.book).decision.rate ==
      newDecimal("0.055")
    # no rule for software to consumers: rejected, since this seller is restricted
    check not nexus.taxFor(address("fr"), btB2C, GoodsType.software).allowed

  test "the first matching rule wins":
    let nexus = Nexus(seller: "acme", source: "de", fallback: Fallback.reject, rules: @[
      rule("fr", "0.055", goods = {GoodsType.book}),
      rule("fr", "0.20")])
    check nexus.taxFor(address("fr"), btB2C, GoodsType.book).decision.rate ==
      newDecimal("0.055")
    check nexus.taxFor(address("fr"), btB2C, GoodsType.physical).decision.rate ==
      newDecimal("0.20")

suite "fallback":
  test "a restricted seller may not sell to other destinations":
    let lookup = fromGb.taxFor(address("us"), btB2C, GoodsType.physical)
    check not lookup.allowed
    check "'us'" in lookup.reason
    check "acme" in lookup.reason
    check "'gb'" in lookup.reason

  test "a worldwide seller sells without tax where it has no rule":
    let lookup = worldwide.taxFor(address("jp"), btB2C, GoodsType.software)
    check lookup.allowed
    check lookup.decision.rate == newDecimal("0.00")
    check lookup.decision.treatment == TaxTreatment.zeroRated
    check "'jp'" in lookup.decision.reason

  test "explicit rules win over the fallback":
    check worldwide.taxFor(address("us"), btB2C, GoodsType.physical).decision.rate ==
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
    check registry.taxFor("acme", "gb", address("gb"), btB2C, GoodsType.physical)
      .decision.treatment == TaxTreatment.standard
    check registry.taxFor("acme", "de", address("gb"), btB2C, GoodsType.physical)
      .decision.treatment == TaxTreatment.importDueByCustomer
    check registry.taxFor("globex", "us", address("jp"), btB2C, GoodsType.physical).allowed

  test "selling without a nexus is not allowed":
    let lookup = registry.taxFor("acme", "fr", address("fr"), btB2C, GoodsType.physical)
    check not lookup.allowed
    check "no nexus" in lookup.reason
    check "'fr'" in lookup.reason
    check not registry.taxFor("nobody", "gb", address("gb"), btB2C, GoodsType.physical).allowed

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
    let taxed = registry.applyTax(lineItem("acme", "gb", netPrice), address("gb"))
    check taxed.allowed
    check taxed.decision.treatment == TaxTreatment.standard
    check taxed.price.taxRate == newDecimal("0.20")
    check taxed.price.net == newMoney("100.00", curEur)
    check taxed.price.tax == newMoney("20.00", curEur)
    check taxed.price.gross == newMoney("120.00", curEur)

  test "a gross price contains the tax":
    let taxed = registry.applyTax(lineItem("acme", "gb", grossPrice), address("gb"))
    check taxed.allowed
    check taxed.price.gross == newMoney("120.00", curEur)
    check taxed.price.net == newMoney("100.00", curEur)
    check taxed.price.tax == newMoney("20.00", curEur)

  test "the delivery source decides: the same item and buyer, other tax":
    let item = lineItem("acme", "de", netPrice)
    let crossBorder = registry.applyTax(item, address("gb"))
    check crossBorder.allowed
    check crossBorder.decision.treatment == TaxTreatment.importDueByCustomer
    check crossBorder.price.tax == newMoney("0.00", curEur)
    check crossBorder.price.gross == newMoney("100.00", curEur)
    # delivered from gb instead
    let domestic = registry.applyTax(item.withSource("gb"), address("gb"))
    check domestic.price.tax == newMoney("20.00", curEur)

  test "the line item is returned unchanged":
    let item = lineItem("acme", "gb", netPrice, goods = GoodsType.book, business = btB2B)
    var reg = NexusRegistry()
    reg.add Nexus(seller: "acme", source: "gb", fallback: Fallback.reject, rules: @[
      rule("gb", "0.00", goods = {GoodsType.book}, business = {btB2B},
           treatment = TaxTreatment.zeroRated)])
    let taxed = reg.applyTax(item, address("gb"))
    check taxed.allowed
    check taxed.item == item
    check taxed.price.raw == item.price.raw
    check taxed.price.priceType == PriceType.net
    check taxed.price.taxRate == newDecimal("0.00")

  test "a sale that is not allowed says why":
    let taxed = registry.applyTax(lineItem("acme", "gb", netPrice), address("us"))
    check not taxed.allowed
    check "'us'" in taxed.reason
    let unknown = registry.applyTax(lineItem("nobody", "gb", netPrice), address("gb"))
    check not unknown.allowed
    check "no nexus" in unknown.reason

  test "a worldwide seller sells without tax":
    let taxed = registry.applyTax(lineItem("globex", "us", netPrice), address("jp"))
    check taxed.allowed
    check taxed.price.tax == newMoney("0.00", curEur)
    check taxed.price.gross == newMoney("100.00", curEur)

  test "the lookup of a line item matches the lookup by its fields":
    let item = lineItem("acme", "gb", netPrice)
    check registry.taxFor(item, address("gb")).decision.rate ==
      registry.taxFor("acme", "gb", address("gb"), btB2C, GoodsType.physical).decision.rate
