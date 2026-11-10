import unittest
import shopbits

suite "money":
  test "formatting and arithmetic":
    check $newMoney("1.00", curEur) == "1.00 EUR"
    check (newMoney("1.00", curEur) + newMoney("1.00", curEur)) == newMoney("2.00", curEur)
    check (newMoney("2.00", curEur) - newMoney("1.05", curEur)) == newMoney("0.95", curEur)

suite "prices":
  let price1 = (newMoney("100.00", curEur), newDecimal("0.19"), PriceType.net)
  let price2 = (newMoney("119.00", curEur), newDecimal("0.19"), PriceType.gross)

  test "gross":
    check price1.gross == newMoney("119.00", curEur)
    check price2.gross == newMoney("119.00", curEur)

  test "net":
    check price1.net == newMoney("100.00", curEur)
    check price2.net == newMoney("100.00", curEur)

  test "tax":
    check price1.tax == newMoney("19.00", curEur)
    check price2.tax == newMoney("19.00", curEur)

suite "catalog prices":
  test "a catalog price becomes an order price once the tax rate is known":
    let net: CatalogPrice = (newMoney("100.00", curEur), PriceType.net)
    let gross: CatalogPrice = (newMoney("119.00", curEur), PriceType.gross)
    check net.withTax(newDecimal("0.19")).gross == newMoney("119.00", curEur)
    check gross.withTax(newDecimal("0.19")).net == newMoney("100.00", curEur)
    check net.withTax(newDecimal("0.19")).tax == newMoney("19.00", curEur)

  test "the same quoted price has different amounts under different rates":
    let net: CatalogPrice = (newMoney("100.00", curEur), PriceType.net)
    check net.withTax(newDecimal("0.07")).gross == newMoney("107.00", curEur)
    check net.withTax(newDecimal("0.00")).gross == newMoney("100.00", curEur)

  test "a price without tax has no gross, net or tax amounts (it does not compile)":
    let net: CatalogPrice = (newMoney("100.00", curEur), PriceType.net)
    check not compiles(net.gross)
    check not compiles(net.tax)
    check compiles(net.value)

suite "tax regions":
  test "region is derived from the country code":
    let address = TaxAddress(postal_code: "10407", region: "Berlin", country_code: "de")
    check address.country_code == taxAddressToTaxRegion(address)
