## Tax nexus: which tax rules apply to a sale.
##
## Which tax applies to a sale depends on *who sells it* and *where the goods
## are delivered from*, not only on where the customer lives. A seller who ships
## from a warehouse in the customer's own country makes a domestic sale; the
## same seller shipping from a warehouse abroad makes a cross-border sale with
## different rules (and another seller may follow completely different rules).
##
## A `Nexus` is the combination of a **seller** and a **delivery source** (the
## tax region the goods are delivered from). It owns a complete set of
## `TaxRule`s and says what happens for destinations that have no rule:
##
## * `Fallback.reject`: the seller may only sell to the destinations it has
##   rules for; anything else is not allowed.
## * `Fallback.zeroTax`: the seller sells worldwide, with no tax where there is
##   no rule.
##
## A rule matches the buyer's tax region, the goods type and the business type of
## the sale, and gives a rate together with a `TaxTreatment` and a reason, so an
## invoice can say *why* the rate is what it is (e.g. "import tax is payable by
## the customer").
##
## A sale can have **several taxes** (say a general tax and a specific levy). A
## rule says which tax it is for (`TaxRule.tax`, `DefaultTax` if there is only
## one kind). Rules for the same tax compete (see below), rules for different
## taxes are independent: every tax that has a matching rule gives one `TaxLine`
## of the result, in the order in which the taxes first appear in the rules. All
## taxes are computed on the same net amount.
##
## .. code-block:: nim
##   import shopbits
##   import shopbits/tax_nexus
##
##   var registry = NexusRegistry()
##   registry.add Nexus(seller: "acme", source: "de", fallback: Fallback.reject, rules: @[
##     TaxRule(destination: "de", goodsTypes: {GoodsType.physical},
##             businessTypes: {btB2C}, rate: newDecimal("0.19"))])
##
##   let buyer = TaxAddress(country_code: "de")
##   let lookup = registry.taxFor("acme", "de", buyer, btB2C, GoodsType.physical,
##                                initDate(2026, 6, 15))
##   assert lookup.allowed and lookup.decision.totalRate == newDecimal("0.19")
##
## For each tax, the rules are checked in order and the first match wins, so put
## specific rules before general ones. Tax regions are compared exactly (they are
## the country codes of `taxAddressToTaxRegion`).
##
## Rules can be **effective for a period**: a rule with `validFrom` and/or
## `validUntil` (both inclusive) only applies on days in that period, so a rate
## change can be entered in advance, and a sale on a past day is taxed with the
## rule that was effective then. Every lookup therefore takes the day (`asOf`) it
## is for; there is deliberately no default, so a result never silently depends on
## today's date.
##
## A `LineItem` (which names the seller and the delivery source) has a
## `CatalogPrice` without any tax: the tax is only known once all information
## about the sale is available. `applyTax` looks up the nexus and returns the
## price as an `OrderPrice` with the tax lines of the nexus, which has the gross,
## net and tax amounts. A net price gets the taxes on top, a gross price contains
## the taxes at the rates of the nexus.

import std/options
import ../shopbits, date

export date

type
  Fallback* {.pure.} = enum
    ## What a nexus does for a destination it has no rule for.
    reject   ## the seller may not sell there
    zeroTax  ## the seller sells there without tax

  TaxRule* = object
    ## The tax for sales to `destination` of the given goods and business types.
    tax*: string = DefaultTax
      ## which tax this rule is for; for each tax, the first matching rule wins
    destination*: string
    goodsTypes*: set[GoodsType]
    businessTypes*: set[BusinessType]
    rate*: Decimal
    treatment*: TaxTreatment
    reason*: string  ## optional explanation, e.g. for invoices
    validFrom*: Option[Date]
      ## the first day the rule is effective; none: it has always been
    validUntil*: Option[Date]
      ## the last day the rule is effective; none: it stays effective

  Nexus* = object
    ## The rules of one seller delivering from one tax region.
    seller*: string
    source*: string  ## tax region the goods are delivered from
    rules*: seq[TaxRule]
    fallback*: Fallback

  NexusRegistry* = object
    ## All the nexuses; there is at most one per seller and delivery source.
    nexuses: seq[Nexus]

  TaxDecision* = object
    ## The taxes of a sale.
    lines*: seq[TaxLine]
      ## one for each tax that has a matching rule, in the order in which the
      ## taxes first appear in the rules; empty if no tax is charged
    reason*: string
      ## set if no rule matched and the seller sells there without tax

  TaxLookup* = object
    ## The result of looking up the tax of a sale. A sale that is not allowed
    ## is a normal outcome, not an error, so it is returned, with the reason.
    case allowed*: bool
    of true: decision*: TaxDecision
    of false: reason*: string

  TaxedLineItem* = object
    ## The result of applying the tax of the nexus to a line item.
    case allowed*: bool
    of true:
      item*: LineItem  ## the line item, unchanged
      price*: OrderPrice  ## the price of one article with the tax lines of the decision
      decision*: TaxDecision
    of false: reason*: string

const
  AllGoodsTypes* = {GoodsType.physical .. GoodsType.book}
  AllBusinessTypes* = {btB2C, btB2B}

func totalRate*(decision: TaxDecision): Decimal =
  ## The sum of the rates of all the taxes of the decision.
  decision.lines.totalRate

# registry

proc find*(registry: NexusRegistry, seller, source: string): Option[Nexus] =
  ## The nexus of a seller delivering from `source`, if there is one.
  for nexus in registry.nexuses:
    if nexus.seller == seller and nexus.source == source:
      return some(nexus)
  none(Nexus)

proc add*(registry: var NexusRegistry, nexus: Nexus) =
  ## Add a nexus. Raises `ValueError` if there already is one for the seller and
  ## the delivery source.
  if registry.find(nexus.seller, nexus.source).isSome:
    raise newException(ValueError,
      "there already is a nexus for seller '" & nexus.seller &
      "' delivering from '" & nexus.source & "'")
  registry.nexuses.add nexus

func len*(registry: NexusRegistry): int =
  ## The number of nexuses.
  registry.nexuses.len

iterator items*(registry: NexusRegistry): Nexus =
  ## The nexuses, in the order they were added.
  for nexus in registry.nexuses:
    yield nexus

# looking up the tax

func isEffectiveOn*(rule: TaxRule, day: Date): bool =
  ## Is the rule effective on `day`? Both ends of the period are inclusive.
  (rule.validFrom.isNone or rule.validFrom.get <= day) and
    (rule.validUntil.isNone or day <= rule.validUntil.get)

func matches(rule: TaxRule, destination: string, businessType: BusinessType,
             goodsType: GoodsType, asOf: Date): bool =
  rule.destination == destination and
    goodsType in rule.goodsTypes and businessType in rule.businessTypes and
    rule.isEffectiveOn(asOf)

proc taxFor*(nexus: Nexus, buyer: TaxAddress, businessType: BusinessType,
             goodsType: GoodsType, asOf: Date): TaxLookup =
  ## The tax for selling `goodsType` to `buyer` on the day `asOf` under the rules
  ## of the nexus that are effective on that day.
  let destination = taxAddressToTaxRegion(buyer)
  # The lines follow the order in which the taxes first appear in the rules, no
  # matter which rule of a tax wins.
  var taxes: seq[string]
  for rule in nexus.rules:
    if rule.tax notin taxes: taxes.add rule.tax
  var lines: seq[TaxLine]
  for tax in taxes:
    for rule in nexus.rules:
      if rule.tax == tax and rule.matches(destination, businessType, goodsType, asOf):
        lines.add TaxLine(tax: rule.tax, rate: rule.rate, treatment: rule.treatment,
                          reason: rule.reason)
        break
  if lines.len > 0:
    return TaxLookup(allowed: true, decision: TaxDecision(lines: lines))
  case nexus.fallback
  of Fallback.zeroTax:
    TaxLookup(allowed: true, decision: TaxDecision(
      reason: "no tax rule for '" & destination & "' on " & $asOf &
              ", no tax is charged"))
  of Fallback.reject:
    TaxLookup(allowed: false, reason:
      "seller '" & nexus.seller & "' delivering from '" & nexus.source &
      "' may not sell to '" & destination & "' on " & $asOf)

proc taxFor*(registry: NexusRegistry, seller, source: string, buyer: TaxAddress,
             businessType: BusinessType, goodsType: GoodsType, asOf: Date): TaxLookup =
  ## Like `taxFor` for a nexus, looking up the nexus of `seller` delivering from
  ## `source` first. Selling without a nexus is not allowed.
  let nexus = registry.find(seller, source)
  if nexus.isNone:
    return TaxLookup(allowed: false, reason:
      "seller '" & seller & "' has no nexus for deliveries from '" & source & "'")
  nexus.get.taxFor(buyer, businessType, goodsType, asOf)

# line items

proc taxFor*(registry: NexusRegistry, item: LineItem, buyer: TaxAddress,
             asOf: Date): TaxLookup =
  ## Like `taxFor`, with the seller, delivery source, business type and goods type
  ## of the line item.
  registry.taxFor(item.seller, item.deliverySource, buyer, item.businessType,
                  item.article.goodsType, asOf)

proc applyTax*(registry: NexusRegistry, item: LineItem, buyer: TaxAddress,
               asOf: Date): TaxedLineItem =
  ## Apply the tax of the nexus of `item` to its price. If the seller may not sell
  ## the item to `buyer`, the result says why.
  let lookup = registry.taxFor(item, buyer, asOf)
  if not lookup.allowed:
    return TaxedLineItem(allowed: false, reason: lookup.reason)
  TaxedLineItem(allowed: true, item: item,
                price: item.price.withTax(lookup.decision.lines),
                decision: lookup.decision)
