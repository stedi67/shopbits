import
  shopbits/pm_decimals

export pm_decimals

type
  PriceType* {.pure.} = enum
    net, gross

  BusinessType* = enum
    btB2C, btB2B

  Currency* = enum
    curEur="EUR", curUsd="USD"

  Money* = tuple[amount: Decimal, currency: Currency]

  Country* = object
    country_code*: string
    allow_shipment*: bool

  GoodsType* {.pure.} = enum
    physical, software, book

  TaxAddress* = object
    postal_code*: string
    region*: string
    country_code*: string

  # How the tax of a sale is handled.
  TaxTreatment* {.pure.} = enum
    standard             ## the seller charges the rate
    reverseCharge        ## the customer accounts for the tax
    zeroRated            ## taxable at a rate of zero
    exempt               ## not subject to tax
    importDueByCustomer  ## import tax is payable by the customer on delivery

  # One tax of a sale. A sale can have several taxes, e.g. a general tax and a
  # specific levy, one line each.
  TaxLine* = object
    tax*: string  ## which tax this is, e.g. "vat" or "levy"
    rate*: Decimal
    treatment*: TaxTreatment
    reason*: string  ## optional explanation, e.g. for invoices

  # A price as it is quoted in the catalog, net or gross. It says nothing about
  # tax: the tax is only known once all information about the sale is available
  # (see `shopbits/tax_nexus`), which turns it into an `OrderPrice`.
  CatalogPrice* = tuple
    raw: Money
    priceType: PriceType

  # The price in an order: a catalog price together with the taxes that apply
  # to the sale (none, one or several). Only this has gross, net and tax amounts.
  OrderPrice* = tuple
    raw: Money
    taxes: seq[TaxLine]
    priceType: PriceType

  Article* = object
    id*: string
    name*: string
    goodsType*: GoodsType

  LineItem* = object
    price*: CatalogPrice
      ## the catalog price of one article; the tax is applied by the tax
      ## nexus (see `shopbits/tax_nexus`)
    businessType*: BusinessType
    article*: Article
    quantity*: int
    seller*: string
      ## who sells the article; together with the delivery source it selects
      ## the tax rules
    deliverySource*: string
      ## the tax region the article is delivered from; for goods that are not
      ## delivered physically, the home region of the seller

  LineItemRef* = ref LineItem

# tax region
proc taxAddressToTaxRegion*(address: TaxAddress): string =
  result = address.country_code

# money
proc newMoney*(value: string, currency:Currency): Money =
  result = (newDecimal(value), currency)

proc `$`*(money: Money): string =
  result = $money.amount & ' ' & $money.currency

proc `+`*(a, b:Money): Money =
  assert(a.currency == b.currency)
  result = (a.amount + b.amount, a.currency)

proc `-`*(a, b:Money): Money =
  assert(a.currency == b.currency)
  result = (a.amount - b.amount, a.currency)

# prices
const DefaultTax* = "tax"
  ## The name of the tax of a tax line when there is only one kind of tax.

proc value*(price: CatalogPrice | OrderPrice): Decimal =
  result = price.raw.amount

func taxLine*(tax: string, rate: string, treatment = TaxTreatment.standard,
              reason = ""): TaxLine =
  ## A tax line with the rate given as a string, e.g. ``taxLine("vat", "0.19")``.
  TaxLine(tax: tax, rate: newDecimal(rate), treatment: treatment, reason: reason)

proc withTax*(price: CatalogPrice, taxes: seq[TaxLine]): OrderPrice =
  ## The price in an order, now that the taxes of the sale are known.
  (price.raw, taxes, price.priceType)

proc withTax*(price: CatalogPrice, rate: Decimal): OrderPrice =
  ## The price in an order with one tax, named `DefaultTax`, at `rate`.
  price.withTax(@[TaxLine(tax: DefaultTax, rate: rate)])

proc totalRate*(taxes: seq[TaxLine]): Decimal =
  ## The sum of the rates of the tax lines. (All taxes are computed on the same
  ## net amount, a tax is not charged on top of another tax.)
  result = (0'i64, 0.int8)
  for line in taxes:
    result = result + line.rate

proc totalRate*(price: OrderPrice): Decimal =
  price.taxes.totalRate

proc taxAmounts*(price: OrderPrice): seq[Money] =
  ## The amount of each tax line, in the order of the lines, each rounded to the
  ## precision of the price. The total tax is the sum of these, so that net, tax
  ## and gross always add up exactly.
  let
    x = price.value
    currency = price.raw.currency
  case price.priceType:
    of PriceType.net:
      for line in price.taxes:
        result.add (((x * line.rate).toPrecision(x.prec)), currency)
    of PriceType.gross:
      # the tax contained in a gross price: x * rate / (1 + total rate)
      if price.taxes.len > 0:
        let share = inv (newDecimal("1.0") + price.totalRate)
        for line in price.taxes:
          result.add (((x * line.rate * share).toPrecision(x.prec)), currency)

proc tax*(price: OrderPrice): Money =
  ## The total tax.
  result = ((0'i64, price.value.prec), price.raw.currency)
  for amount in price.taxAmounts:
    result = result + amount

proc gross*(price: OrderPrice): Money =
  case price.priceType:
    of PriceType.gross: result = price.raw
    of PriceType.net: result = price.raw + price.tax

proc net*(price: OrderPrice): Money =
  case price.priceType:
    of PriceType.gross: result = price.raw - price.tax
    of PriceType.net: result = price.raw
