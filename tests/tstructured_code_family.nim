## Tests of `defineCodeFamily` with a made-up family of codes.
import std/[unittest, hashes, options, strutils]
import shopbits/structured_code

const
  numberLayout = Layout(name: "number", prefix: "N", prefixExcept: @["Nx"], slots: @[
    slot("flag", 1), slot("amount", 3)])
  wordLayout = Layout(name: "word", slots: @[   # the fallback: no prefix
    slot("text", 4), slot("tag", 2)])
  xaLayout = Layout(name: "xa", prefix: "Xa", slots: @[
    slot("flag", 2), slot("rest", 4)])
  toyKinds = @[wordLayout, numberLayout, xaLayout]

defineCodeFamily(Kind, AnyToy, toyKinds, "k")

suite "kinds":
  test "the enum has a member for each layout, in the order of the list":
    check Kind.low == kWord
    check Kind.high == kXa
    check $kNumber == "number"
    check ord(kWord) == 0 and ord(kNumber) == 1 and ord(kXa) == 2

  test "layouts and lengths":
    check layoutOf(kNumber).name == "number"
    check layoutOf(kWord).codeLen == 6
    check codeLen(kNumber) == 4
    check codeLen(kXa) == 6

  test "the fallback excludes the prefixes of the others, derived":
    let excluded = layoutOf(kWord).excluded
    check excluded.len == 2
    check excluded[0].prefix == "N"
    check excluded[0].exceptions == @["Nx"]
    check excluded[1].prefix == "Xa"
    check layoutOf(kNumber).excluded.len == 0  # only the fallback has them
    # the layout in the list itself is not changed
    check wordLayout.excluded.len == 0

  test "dispatching":
    check Kind.dispatch("N123") == kNumber
    check Kind.dispatch("XaABCD") == kXa
    check Kind.dispatch("abcdef") == kWord
    check Kind.dispatch("Nxabcd") == kWord  # an exception of the number prefix
    check Kind.dispatch("") == kWord
    check Kind.dispatch("N") == kNumber

  test "validity per kind":
    check isValidCode(kNumber, "N123")
    check not isValidCode(kNumber, "N12")
    check not isValidCode(kNumber, "Nx12")
    check isValidCode(kWord, "Nxabcd")  # starts like a number, but is an exception

suite "types":
  test "a type and a query type for each layout":
    check $NumberCode.parse("N123") == "N123"
    check $WordCode.parse("abcdef") == "abcdef"
    check $XaCode.parse("XaABCD") == "XaABCD"
    check NumberCode.parse("N123").amount == "123"
    check WordCode.parse("abcdef").tag == "ef"
    check $NumberQuery.fromAmount("12?") == "N12?"
    check $WordQuery.fromTag("ef") == "????ef"

  test "kindOf":
    check kindOf(NumberCode) == kNumber
    check kindOf(WordCode) == kWord
    check kindOf(XaCode) == kXa

  test "the types are distinct":
    let n = NumberCode.parse("N123")
    check not compiles(n == WordCode.parse("abcdef"))
    check not compiles(n.text)
    check compiles(n.amount)

suite "any code":
  test "parsing dispatches by itself":
    let
      n = AnyToy.parse("N123")
      w = AnyToy.parse("abcdef")
      c = AnyToy.parse("XaABCD")
    check n.kind == kNumber and w.kind == kWord and c.kind == kXa
    check n.number.amount == "123"
    check w.word.text == "abcd"
    check c.xa.rest == "ABCD"

  test "raw, printing, equality and hashing":
    let n = AnyToy.parse("N123")
    check n.raw == "N123"
    check $n == "N123"
    check n == AnyToy.parse("N123")
    check n != AnyToy.parse("N124")
    check hash(n) == hash(AnyToy.parse("N123"))

  test "conversion from a code of a known kind":
    check toAnyToy(NumberCode.parse("N123")) == AnyToy.parse("N123")
    check toAnyToy(WordCode.parse("abcdef")).kind == kWord
    check not compiles(toAnyToy("N123"))

  test "invalid codes":
    check AnyToy.tryParse("N12").isNone
    check AnyToy.tryParse("N123 ").isNone
    check AnyToy.tryParse("Nx12").isNone  # a word, which is too short
    check AnyToy.tryParse("N123").isSome
    expect StructuredCodeError:
      discard AnyToy.parse("N12")
    try:
      discard AnyToy.parse("N12")
    except StructuredCodeError as e:
      check "number" in e.msg  # the message is about the kind it looked like

  test "case statements over the kinds are checked for completeness":
    # (this compiles because all kinds are handled)
    proc describe(c: AnyToy): string =
      case c.kind
      of kWord: "word"
      of kNumber: "number"
      of kXa: "xa"
    check describe(AnyToy.parse("N123")) == "number"
    check not compiles((proc (c: AnyToy): string =
      case c.kind
      of kWord: "word"
      of kNumber: "number"))
