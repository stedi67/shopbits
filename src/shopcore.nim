import
  shopcore/pm_decimals

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

  Tax* = object
    id*: int
    tax_region*: string
    goods_type*: GoodsType
    rate*: Decimal

  TaxAddress* = object
    postal_code*: string
    region*: string
    country_code*: string

  Price* = tuple
    raw: Money
    taxRate: Decimal
    priceType: PriceType

  Article* = object
    id*: string
    name*: string
    goodsType*: GoodsType

  LineItem* = object
    b2bTax*: Tax
    b2cTax*: Tax
    price*: Price
    businessType*: BusinessType
    article*: Article
    quantity*: int

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
proc value*(price: Price): Decimal =
  result = price.raw.amount

proc gross*(price: Price): Money =
  case price.priceType:
    of PriceType.gross:
      result = price.raw
    of PriceType.net:
      let x = price.value
      let rate = price.tax_rate
      let new_value = (x + x * rate).toPrecision(x.prec)
      result = (new_value, price.raw.currency)

proc net*(price: Price): Money =
  case price.priceType:
    of PriceType.gross:
      let x = price.value
      let rate = price.tax_rate
      let new_value = (x - (x * rate * (inv (newDecimal("1.0")+rate)))).toPrecision(x.prec)
      result = (new_value, price.raw.currency)
    of PriceType.net:
      result = price.raw

proc tax*(price: Price): Money =
  result = price.gross - price.net
