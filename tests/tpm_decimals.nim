import unittest
import shopcore/pm_decimals

suite "pm_decimals":
  test "parsing and formatting":
    check $newDecimal("0.1") == "0.1"
    check $newDecimal("0.01") == "0.01"
    check $newDecimal("1.00") == "1.00"
    check $newDecimal("10.24") == "10.24"
    check $newDecimal("-1.0") == "-1.0"
    check $newDecimal("2.") == "2."

  test "toPrecision":
    let a = toPrecision((100i64, 0.int8), 1)
    let b = (1000i64, 1.int8)
    check $a == $b
    check $a == "100.0"
    check newDecimal("1.005").toPrecision(2) == newDecimal("1.01")
    check newDecimal("1.0049").toPrecision(2) == newDecimal("1.00")

  test "addition and subtraction":
    check (newDecimal("0.12") + newDecimal("1.32")) == newDecimal("1.44")
    check (newDecimal("0.12") - newDecimal("1.00")) == newDecimal("-0.88")

  test "equality ignores trailing zeros":
    check newDecimal("0.120") == newDecimal("0.12")

  test "multiplication":
    let c = -2 * newDecimal("0.1")
    check (2 * newDecimal("0.1")) == newDecimal("0.2")
    check (-2 * newDecimal("0.1")) == newDecimal("-0.2")
    check $c == "-0.2"
    check (newDecimal("2.00") * newDecimal("2.00")) == newDecimal("4.0000")
    check (newDecimal("100.00") * newDecimal("0.19")) == newDecimal("19.0000")

  test "comparison":
    check newDecimal("1.1") > newDecimal("1.0")
    check newDecimal("-1.1") < newDecimal("-1.0")
    check newDecimal("1.1") >= newDecimal("1.0")
    check newDecimal("-1.1") <= newDecimal("-1.0")
    check newDecimal("1.1") >= newDecimal("1.1")
    check newDecimal("1.1") <= newDecimal("1.1")

  test "inverse":
    check (inv newDecimal("0.5")).toPrecision(1) == newDecimal("2.0")
    check (inv newDecimal("125.0")).toPrecision(4) == newDecimal("0.008")
    check (inv newDecimal("1.19")).toPrecision(2) == newDecimal("0.84")
    check (newDecimal("22.61") * newDecimal("1.19").inv).toPrecision(2) == newDecimal("19.00")
