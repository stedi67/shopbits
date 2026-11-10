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

suite "exact tax amounts":
  test "a gross price with a rate that has many decimals (inv used to lose a cent)":
    let price = (newMoney("100.00", curEur), PriceType.gross).withTax(newDecimal("0.0825"))
    check price.tax == newMoney("7.62", curEur)  # 100 * 0.0825 / 1.0825 = 7.6212
    check price.net == newMoney("92.38", curEur)
    check price.gross == newMoney("100.00", curEur)

  test "a net price with a rate that has many decimals":
    let price = (newMoney("100.00", curEur), PriceType.net).withTax(newDecimal("0.0825"))
    check price.tax == newMoney("8.25", curEur)
    check price.gross == newMoney("108.25", curEur)

  test "halves are rounded up":
    # 0.50 * 0.01 = 0.005 -> 0.01, 0.10 * 0.05 = 0.005 -> 0.01
    check (newMoney("0.50", curEur), PriceType.net).withTax(newDecimal("0.01")).tax ==
      newMoney("0.01", curEur)
    check (newMoney("0.10", curEur), PriceType.net).withTax(newDecimal("0.05")).tax ==
      newMoney("0.01", curEur)
    # 1.49 * 0.1 = 0.149 -> 0.15, 1.44 * 0.1 = 0.144 -> 0.14
    check (newMoney("1.49", curEur), PriceType.net).withTax(newDecimal("0.1")).tax ==
      newMoney("0.15", curEur)
    check (newMoney("1.44", curEur), PriceType.net).withTax(newDecimal("0.1")).tax ==
      newMoney("0.14", curEur)

  test "rates with different numbers of decimals can be mixed":
    let price = (newMoney("200.00", curEur), PriceType.net).withTax(
      @[taxLine("a", "0.19"), taxLine("b", "0.055"), taxLine("c", "0.0125")])
    let amounts = price.taxAmounts
    check amounts[0] == newMoney("38.00", curEur)
    check amounts[1] == newMoney("11.00", curEur)
    check amounts[2] == newMoney("2.50", curEur)

  test "the amounts of other precisions":
    # a whole amount: a value of 100 with no decimals
    let whole: Money = ((100'i64, 0'i8), curEur)
    let tax = (whole, PriceType.net).withTax(newDecimal("0.19")).tax
    check tax.amount.value == 19
    check tax.amount.prec == 0
    check (newMoney("10.0000", curEur), PriceType.net).withTax(newDecimal("0.0825")).tax ==
      newMoney("0.8250", curEur)

  test "the amounts agree with exact rational arithmetic":
    # computed independently with fractions, rounding halves up
    const cases = [
    ("100.00", PriceType.gross, @["0.00"], @["0.00"]),
    ("100.00", PriceType.net, @["0.00"], @["0.00"]),
    ("1.00", PriceType.gross, @["0.00"], @["0.00"]),
    ("19999.99", PriceType.net, @["0.1234", "0.05"], @["2468.00", "1000.00"]),
    ("0.99", PriceType.gross, @["1.0"], @["0.50"]),
    ("1.00", PriceType.net, @["0.0825"], @["0.08"]),
    ("1234.56", PriceType.gross, @["0.000001"], @["0.00"]),
    ("19999.99", PriceType.net, @["0.1234", "0.05"], @["2468.00", "1000.00"]),
    ("1234.56", PriceType.net, @["0.19"], @["234.57"]),
    ("0.01", PriceType.net, @["0.19"], @["0.00"]),
    ("9.99", PriceType.net, @["0.1234", "0.05"], @["1.23", "0.50"]),
    ("7.77", PriceType.gross, @["1.0"], @["3.89"]),
    ("100.00", PriceType.net, @["0.1234", "0.05"], @["12.34", "5.00"]),
    ("119.00", PriceType.gross, @["0.19", "0.055"], @["18.16", "5.26"]),
    ("100.00", PriceType.net, @["0.19"], @["19.00"]),
    ("100.00", PriceType.gross, @["0.2"], @["16.67"]),
    ("119.00", PriceType.gross, @["0.0825"], @["9.07"]),
    ("33.33", PriceType.gross, @["0.19", "0.055"], @["5.09", "1.47"]),
    ("0.01", PriceType.net, @["0.0825"], @["0.00"]),
    ("99.99", PriceType.gross, @["0.0825"], @["7.62"]),
    ("99.99", PriceType.net, @["0.0825"], @["8.25"]),
    ("19999.99", PriceType.net, @["0.19"], @["3800.00"]),
    ("9.99", PriceType.gross, @["0.19"], @["1.60"]),
    ("99.99", PriceType.gross, @["0.000001"], @["0.00"]),
    ("0.99", PriceType.net, @["0.1234", "0.05"], @["0.12", "0.05"]),
    ("7.77", PriceType.gross, @["0.2"], @["1.30"]),
    ("0.99", PriceType.gross, @["0.2"], @["0.17"]),
    ("0.01", PriceType.net, @["0.000001"], @["0.00"]),
    ("1.00", PriceType.net, @["0.19", "0.055"], @["0.19", "0.06"]),
    ("0.01", PriceType.gross, @["0.19"], @["0.00"]),
    ("7.77", PriceType.net, @["1.0"], @["7.77"]),
    ("19999.99", PriceType.net, @["0.00"], @["0.00"]),
    ("100.00", PriceType.net, @["0.00"], @["0.00"]),
    ("0.50", PriceType.gross, @["0.07", "0.02"], @["0.03", "0.01"]),
    ("19999.99", PriceType.net, @["0.000001"], @["0.02"]),
    ("99.99", PriceType.net, @["0.000001"], @["0.00"]),
    ("0.01", PriceType.gross, @["0.2"], @["0.00"]),
    ("0.01", PriceType.net, @["0.19", "0.055"], @["0.00", "0.00"]),
    ("99.99", PriceType.net, @["0.1234", "0.05"], @["12.34", "5.00"]),
    ("0.01", PriceType.net, @["0.07", "0.02"], @["0.00", "0.00"]),
    ("100.00", PriceType.net, @["0.2"], @["20.00"]),
    ("7.77", PriceType.gross, @["0.1234", "0.05"], @["0.82", "0.33"]),
    ("10.01", PriceType.net, @["0.000001"], @["0.00"]),
    ("0.99", PriceType.net, @["0.0825"], @["0.08"]),
    ("1234.56", PriceType.net, @["0.19", "0.055"], @["234.57", "67.90"]),
    ("1234.56", PriceType.gross, @["0.0775", "0.0125", "0.02"], @["86.20", "13.90", "22.24"]),
    ("1234.56", PriceType.net, @["1.0"], @["1234.56"]),
    ("1234.56", PriceType.net, @["1.0"], @["1234.56"]),
    ("99.99", PriceType.net, @["0.07", "0.02"], @["7.00", "2.00"]),
    ("10.01", PriceType.net, @["0.19", "0.055"], @["1.90", "0.55"]),
    ("0.50", PriceType.net, @["0.19", "0.055"], @["0.10", "0.03"]),
    ("0.50", PriceType.net, @["0.00"], @["0.00"]),
    ("19999.99", PriceType.gross, @["0.000001"], @["0.02"]),
    ("1234.56", PriceType.gross, @["0.0825"], @["94.09"]),
    ("0.01", PriceType.net, @["0.0825"], @["0.00"]),
    ("0.01", PriceType.gross, @["0.00"], @["0.00"]),
    ("9.99", PriceType.gross, @["0.000001"], @["0.00"]),
    ("99.99", PriceType.gross, @["0.1234", "0.05"], @["10.52", "4.26"]),
    ("10.01", PriceType.net, @["0.00"], @["0.00"]),
    ("0.50", PriceType.net, @["0.0825"], @["0.04"]),
    ]
    for (amount, priceType, rates, expected) in cases:
      var lines: seq[TaxLine]
      for i, rate in rates: lines.add taxLine("t" & $i, rate)
      let price = (newMoney(amount, curEur), priceType).withTax(lines)
      let amounts = price.taxAmounts
      check amounts.len == expected.len
      for i, e in expected:
        check amounts[i] == newMoney(e, curEur)
      check price.net + price.tax == price.gross

  test "an amount that is too large to compute is refused, not computed wrongly":
    let huge = (newMoney("9000000000000000.00", curEur), PriceType.net).withTax(newDecimal("0.19"))
    expect ValueError:
      discard huge.tax

  test "negative amounts and rates are refused":
    expect ValueError:
      discard (newMoney("-1.00", curEur), PriceType.net).withTax(newDecimal("0.19")).tax
    expect ValueError:
      discard (newMoney("1.00", curEur), PriceType.net).withTax(@[TaxLine(tax: "x", rate: newDecimal("-0.1"))]).tax
