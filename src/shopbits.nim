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

  # A price as it is quoted in the catalog, net or gross. It says nothing about
  # tax: the tax is only known once all information about the sale is available
  # (see `shopbits/tax_nexus`), which turns it into an `OrderPrice`.
  CatalogPrice* = tuple
    raw: Money
    priceType: PriceType

  # The price in an order: a catalog price together with the tax rate that
  # applies to the sale. Only this has gross, net and tax amounts.
  OrderPrice* = tuple
    raw: Money
    taxRate: Decimal
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
proc value*(price: CatalogPrice | OrderPrice): Decimal =
  result = price.raw.amount

proc withTax*(price: CatalogPrice, rate: Decimal): OrderPrice =
  ## The price in an order, now that the tax rate of the sale is known.
  (price.raw, rate, price.priceType)

proc gross*(price: OrderPrice): Money =
  case price.priceType:
    of PriceType.gross:
      result = price.raw
    of PriceType.net:
      let x = price.value
      let rate = price.tax_rate
      let new_value = (x + x * rate).toPrecision(x.prec)
      result = (new_value, price.raw.currency)

proc net*(price: OrderPrice): Money =
  case price.priceType:
    of PriceType.gross:
      let x = price.value
      let rate = price.tax_rate
      let new_value = (x - (x * rate * (inv (newDecimal("1.0")+rate)))).toPrecision(x.prec)
      result = (new_value, price.raw.currency)
    of PriceType.net:
      result = price.raw

proc tax*(price: OrderPrice): Money =
  result = price.gross - price.net
