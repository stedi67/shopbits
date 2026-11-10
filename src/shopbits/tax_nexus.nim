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
##   let lookup = registry.taxFor("acme", "de", buyer, btB2C, GoodsType.physical)
##   assert lookup.allowed and lookup.decision.rate == newDecimal("0.19")
##
## Rules are checked in order and the first match wins, so put specific rules
## before general ones. Tax regions are compared exactly (they are the country
## codes of `taxAddressToTaxRegion`).
##
## A `LineItem` (which names the seller and the delivery source) has a
## `CatalogPrice` without any tax: the tax is only known once all information
## about the sale is available. `applyTax` looks up the nexus and returns the
## price as an `OrderPrice` with the rate of the nexus, which has the gross, net
## and tax amounts. A net price gets the tax on top, a gross price contains the tax at
## the rate of the nexus.

import std/options
import ../shopbits

type
  TaxTreatment* {.pure.} = enum
    ## How the tax of a sale is handled.
    standard           ## the seller charges the rate
    reverseCharge      ## the customer accounts for the tax
    zeroRated          ## taxable at a rate of zero
    exempt             ## not subject to tax
    importDueByCustomer  ## import tax is payable by the customer on delivery

  Fallback* {.pure.} = enum
    ## What a nexus does for a destination it has no rule for.
    reject   ## the seller may not sell there
    zeroTax  ## the seller sells there without tax

  TaxRule* = object
    ## The tax for sales to `destination` of the given goods and business types.
    destination*: string
    goodsTypes*: set[GoodsType]
    businessTypes*: set[BusinessType]
    rate*: Decimal
    treatment*: TaxTreatment
    reason*: string  ## optional explanation, e.g. for invoices

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
    rate*: Decimal
    treatment*: TaxTreatment
    reason*: string

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
      price*: OrderPrice  ## the price of one article with the rate of the decision
      decision*: TaxDecision
    of false: reason*: string

const
  AllGoodsTypes* = {GoodsType.physical .. GoodsType.book}
  AllBusinessTypes* = {btB2C, btB2B}

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

# looking up the tax

func matches(rule: TaxRule, destination: string, businessType: BusinessType,
             goodsType: GoodsType): bool =
  rule.destination == destination and
    goodsType in rule.goodsTypes and businessType in rule.businessTypes

proc taxFor*(nexus: Nexus, buyer: TaxAddress, businessType: BusinessType,
             goodsType: GoodsType): TaxLookup =
  ## The tax for selling `goodsType` to `buyer` under the rules of the nexus.
  let destination = taxAddressToTaxRegion(buyer)
  for rule in nexus.rules:
    if rule.matches(destination, businessType, goodsType):
      return TaxLookup(allowed: true, decision: TaxDecision(
        rate: rule.rate, treatment: rule.treatment, reason: rule.reason))
  case nexus.fallback
  of Fallback.zeroTax:
    TaxLookup(allowed: true, decision: TaxDecision(
      rate: newDecimal("0.00"), treatment: TaxTreatment.zeroRated,
      reason: "no tax rule for '" & destination & "', no tax is charged"))
  of Fallback.reject:
    TaxLookup(allowed: false, reason:
      "seller '" & nexus.seller & "' delivering from '" & nexus.source &
      "' may not sell to '" & destination & "'")

proc taxFor*(registry: NexusRegistry, seller, source: string, buyer: TaxAddress,
             businessType: BusinessType, goodsType: GoodsType): TaxLookup =
  ## Like `taxFor` for a nexus, looking up the nexus of `seller` delivering from
  ## `source` first. Selling without a nexus is not allowed.
  let nexus = registry.find(seller, source)
  if nexus.isNone:
    return TaxLookup(allowed: false, reason:
      "seller '" & seller & "' has no nexus for deliveries from '" & source & "'")
  nexus.get.taxFor(buyer, businessType, goodsType)

# line items

proc taxFor*(registry: NexusRegistry, item: LineItem, buyer: TaxAddress): TaxLookup =
  ## Like `taxFor`, with the seller, delivery source, business type and goods type
  ## of the line item.
  registry.taxFor(item.seller, item.deliverySource, buyer, item.businessType,
                  item.article.goodsType)

proc applyTax*(registry: NexusRegistry, item: LineItem, buyer: TaxAddress): TaxedLineItem =
  ## Apply the tax of the nexus of `item` to its price. If the seller may not sell
  ## the item to `buyer`, the result says why.
  let lookup = registry.taxFor(item, buyer)
  if not lookup.allowed:
    return TaxedLineItem(allowed: false, reason: lookup.reason)
  TaxedLineItem(allowed: true, item: item,
                price: item.price.withTax(lookup.decision.rate),
                decision: lookup.decision)
