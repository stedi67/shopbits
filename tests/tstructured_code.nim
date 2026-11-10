## Tests of the generic library, with a made-up family of codes that has nothing
## to do with any particular domain.
import std/[unittest, strutils]
import shopcore/structured_code

type Amount = distinct string

proc `==`(a, b: Amount): bool {.borrow.}
proc `$`(a: Amount): string {.borrow.}

const
  # "N123kg": a number, starts with N
  numberLayout = Layout(name: "number", prefix: "N", slots: @[
    slot("flag", 1), slot("amount", 3, "Amount"), slot("unit", 2)])
  # "Nx" belongs to words although it starts with N
  wordLayout = Layout(name: "word", prefixExcept: @[], slots: @[
    slot("text", 4), slot("tag", 2)],
    excluded: @[rule("N", "Nx")])
  # "Cx...": a kind whose prefix has exceptions
  xaLayout = Layout(name: "xa", prefix: "Xa", prefixExcept: @["Xaz"], slots: @[
    slot("flag", 2), slot("rest", 4)])

defineStructuredCode(NumberCode, NumberQuery, numberLayout)
defineStructuredCode(WordCode, WordQuery, wordLayout)
defineStructuredCode(XaCode, XaQuery, xaLayout)

suite "layouts":
  test "length and boundaries":
    check numberLayout.codeLen == 6
    check numberLayout.slotBoundaries == @[0, 1, 4]
    check wordLayout.codeLen == 6

  test "ownership by prefix":
    check numberLayout.owns("N123kg")
    check numberLayout.owns("N")
    check not numberLayout.owns("X123kg")
    check not wordLayout.owns("N123kg")
    check wordLayout.owns("Nx23kg")  # an exception of the excluded prefix
    check wordLayout.owns("abcdef")
    check xaLayout.owns("XaABCD")
    check not xaLayout.owns("XazAB")

  test "validity":
    check numberLayout.isValidCode("N123kg")
    check not numberLayout.isValidCode("N123k")
    check not numberLayout.isValidCode("N123kgg")
    check not numberLayout.isValidCode("N12 kg")
    check not numberLayout.isValidCode("N12?kg")
    check wordLayout.isValidCode("abcdef")
    check not wordLayout.isValidCode("N123kg")

  test "guard patterns":
    check numberLayout.guardPattern == ""
    check wordLayout.guardPattern == "(?!N(?!x))"
    check xaLayout.guardPattern == "(?!Xaz)"

suite "generated code types":
  test "parsing":
    check $NumberCode.parse("N123kg") == "N123kg"
    check NumberCode.tryParse("N123kg").isSome
    check NumberCode.tryParse("nope").isNone
    expect StructuredCodeError:
      discard NumberCode.parse("N123")
    check WordCode.tryParse("N123kg").isNone  # that is a number
    check WordCode.tryParse("abcdef").isSome

  test "the error message names the kind":
    try:
      discard NumberCode.parse("N123")
      fail()
    except StructuredCodeError as e:
      check "number" in e.msg
      check "6 characters" in e.msg
      check "starting with 'N'" in e.msg

  test "accessors, typed and untyped":
    let n = NumberCode.parse("N123kg")
    check n.flag == "N"
    check n.amount == Amount("123")
    check n.unit == "kg"

  test "setters return a changed copy":
    let n = NumberCode.parse("N123kg")
    check $n.withUnit("lb") == "N123lb"
    check $n.withAmount(Amount("999")) == "N999kg"
    check $n == "N123kg"
    expect StructuredCodeError:
      discard n.withUnit("lbs")
    expect StructuredCodeError:
      discard n.withUnit("l?")

  test "the code types are distinct":
    let
      n = NumberCode.parse("N123kg")
      w = WordCode.parse("abcdef")
    check not compiles(n == w)
    check not compiles(n.text)
    check not compiles(w.amount)
    check compiles(n.amount)

  test "the usual operations":
    let a = NumberCode.parse("N123kg")
    check a == NumberCode.parse("N123kg")
    check a < NumberCode.parse("N124kg")
    check a.len == 6
    check a.hash == NumberCode.parse("N123kg").hash

suite "generated queries":
  test "from slots":
    check $NumberQuery.fromUnit("kg") == "N???kg"
    check $NumberQuery.fromAmount("12?") == "N12?" & "??"
    check $NumberQuery.fromSlots(amount = "123", unit = "kg") == "N123kg"
    check $NumberQuery.fromSlots() == "N?????"  # the prefix is part of every query
    check $WordQuery.fromTag("xy") == "????xy"

  test "slot values must fit":
    expect QueryStringError:
      discard NumberQuery.fromUnit("kgs")
    expect QueryStringError:
      discard NumberQuery.fromUnit("k g")
    check not compiles(NumberQuery.fromText("abcd"))
    check not compiles(NumberQuery.fromSlots(text = "abcd"))

  test "membership":
    let kg = NumberQuery.fromUnit("kg")
    check NumberCode.parse("N123kg") in kg
    check NumberCode.parse("N123lb") notin kg
    check NumberCode.parse("N123lb") in (kg or NumberQuery.fromUnit("lb"))

  test "algebra":
    let
      kg = NumberQuery.fromUnit("kg")
      hundred = NumberQuery.fromSlots(amount = "1??")
      code = NumberCode.parse("N123kg")
    check code in (kg and hundred)
    check code notin (kg - hundred)
    check code in (hundred - NumberQuery.fromUnit("lb"))
    check (kg and hundred) <= kg
    check not (kg <= hundred)
    check code notin not kg
    check equivalent(not (not kg), kg)
    check (kg or nullQuery[NumberCode]()) == kg
    check (kg and anyQuery[NumberCode]()) == kg
    check isEmpty(kg and NumberQuery.fromUnit("lb"))

  test "kinds cannot be mixed":
    let
      kg = NumberQuery.fromUnit("kg")
      tag = WordQuery.fromTag("xy")
    check compiles(kg or kg)
    check not compiles(kg or tag)
    check not compiles(kg <= tag)
    check not compiles(NumberCode.parse("N123kg") in tag)

  test "parsing query strings":
    check $parseQuery[NumberCode]("N123") == "N123??"
    check $parseQuery[NumberCode]("N") == "N?????"
    check $parseQuery[NumberCode]("N12.kg") == "N12?kg"  # a dot is a wildcard
    expect IncompatibleQueryError:
      discard parseQuery[NumberCode]("X123")
    expect IncompatibleQueryError:
      discard parseQuery[WordCode]("N123")  # that starts like a number
    check $parseQuery[WordCode]("Nx12") == "Nx12??"
    expect QueryStringError:
      discard parseQuery[NumberCode]("N12")  # not at a slot boundary
    expect QueryStringError:
      discard parseQuery[NumberCode]("N12 ")

  test "a default query is empty":
    var q: NumberQuery
    check isEmpty(q)
    check NumberCode.parse("N123kg") notin q

  test "regular expressions":
    check NumberQuery.fromUnit("kg").toRegexPattern == "^(?:N...kg)$"
    check WordQuery.fromTag("xy").toRegexPattern == "^(?!N(?!x))(?:....xy)$"
    check XaQuery.fromSlots(rest = "ABCD").toRegexPattern == "^(?!Xaz)(?:XaABCD)$"
    check (NumberQuery.fromUnit("kg") - NumberQuery.fromAmount("1??")).toRegexPattern ==
      "^(?:(?!N1....)(?:N...kg))$"
