import unittest
import shopbits

suite "money":
  test "formatting and arithmetic":
    check $newMoney("1.00", curEur) == "1.00 EUR"
    check (newMoney("1.00", curEur) + newMoney("1.00", curEur)) == newMoney("2.00", curEur)
    check (newMoney("2.00", curEur) - newMoney("1.05", curEur)) == newMoney("0.95", curEur)

suite "prices":
  let price1 = (newMoney("100.00", curEur), PriceType.net).withTax(newDecimal("0.19"))
  let price2 = (newMoney("119.00", curEur), PriceType.gross).withTax(newDecimal("0.19"))

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

suite "several taxes":
  let
    net: CatalogPrice = (newMoney("100.00", curEur), PriceType.net)
    gross: CatalogPrice = (newMoney("121.00", curEur), PriceType.gross)
    taxes = @[taxLine("vat", "0.19"), taxLine("levy", "0.02")]

  test "the taxes are added on top of a net price":
    let price = net.withTax(taxes)
    let amounts = price.taxAmounts
    check amounts.len == 2
    check amounts[0] == newMoney("19.00", curEur)
    check amounts[1] == newMoney("2.00", curEur)
    check price.tax == newMoney("21.00", curEur)
    check price.gross == newMoney("121.00", curEur)
    check price.net == newMoney("100.00", curEur)

  test "a gross price contains all the taxes":
    let price = gross.withTax(taxes)
    let amounts = price.taxAmounts
    check amounts[0] == newMoney("19.00", curEur)
    check amounts[1] == newMoney("2.00", curEur)
    check price.tax == newMoney("21.00", curEur)
    check price.net == newMoney("100.00", curEur)
    check price.gross == newMoney("121.00", curEur)

  test "each line is rounded, and the total is the sum of the rounded lines":
    # 10.01 * 0.19 = 1.9019 and 10.01 * 0.02 = 0.2002
    let price = (newMoney("10.01", curEur), PriceType.net).withTax(taxes)
    let amounts = price.taxAmounts
    check amounts[0] == newMoney("1.90", curEur)
    check amounts[1] == newMoney("0.20", curEur)
    check price.tax == newMoney("2.10", curEur)
    check price.gross == newMoney("12.11", curEur)

  test "net and tax always add up to gross":
    for amount in ["0.99", "10.01", "33.33", "99.99", "1234.56"]:
      for priceType in [PriceType.net, PriceType.gross]:
        let price = (newMoney(amount, curEur), priceType).withTax(
          @[taxLine("a", "0.19"), taxLine("b", "0.07"), taxLine("c", "0.02")])
        check price.net + price.tax == price.gross
        check price.tax == price.taxAmounts[0] + price.taxAmounts[1] + price.taxAmounts[2]

  test "no taxes":
    let price = net.withTax(newSeq[TaxLine]())
    check price.taxAmounts.len == 0
    check price.tax == newMoney("0.00", curEur)
    check price.gross == newMoney("100.00", curEur)
    check price.net == newMoney("100.00", curEur)
    let grossPrice = gross.withTax(newSeq[TaxLine]())
    check grossPrice.net == newMoney("121.00", curEur)

  test "the total rate is the sum of the rates":
    check taxes.totalRate == newDecimal("0.21")
    check net.withTax(taxes).totalRate == newDecimal("0.21")
    check newSeq[TaxLine]().totalRate == newDecimal("0.00")

  test "a single rate is one tax line with the default name":
    let price = net.withTax(newDecimal("0.19"))
    check price.taxes.len == 1
    check price.taxes[0].tax == DefaultTax
    check price.taxes[0].treatment == TaxTreatment.standard

  test "a tax line keeps its treatment and reason":
    let line = taxLine("import", "0.00", TaxTreatment.importDueByCustomer, "paid on delivery")
    check line.tax == "import"
    check line.treatment == TaxTreatment.importDueByCustomer
    check line.reason == "paid on delivery"
