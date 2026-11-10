# Poor mans Decimals
# Do some restricted set of decimal operations with 64 bit ints.
# At some point, it might be better to use Rationals for implementation

import
  strutils

type
  Precision = int8
  Decimal* = tuple[value: int64, prec: Precision]

proc reverse(s: string): string =
  result = ""
  for i in countdown(high(s), 0):
    result.add s[i]

iterator digits(number: string): int =
  for c in number:
    if c in {'0'..'9'}:
      yield ord(c) - ord('0')

proc newDecimal*(description: string): Decimal =
  var value = 0i64
  let fac = if description[0] == '-': -1
                                 else: 1

  let rev = description.reverse
  let prec = rev.find(".").int8
  var multiplier = 1
  for num in digits(rev):
    value = value + num * multiplier
    multiplier = multiplier * 10
  let val = (fac*value, prec)
  result = val

proc toPrecision*(x: Decimal, prec: Precision): Decimal =
  let factors = [1, 10, 100, 1000, 10_000, 100_000, 1_000_000, 10_000_000]
  let m = x.prec - prec
  let i = abs(m)
  var newValue = 0i64
  if m > 0:
    let val = x.value div factors[i-1]
    if (val - 5) div 10 != val div 10: # we would need to round down
        newValue = val div 10
    else: # rounding up
        let diff = val - (val div 10) * 10
        newValue = (val + diff) div 10
  else:
      newValue = x.value * factors[i]
  result = (newValue, prec)

proc `$`*(x: Decimal): string =
  result = ""
  let (num, prec) = x
  var s = $abs(num)
  s = s.reverse
  var k = prec - s.len + 1
  while k>0:
    s.add "0"
    k = k-1

  for i in 0..s.len:
    if i < prec:
      result.add s[i]
    elif i == prec:
      result.add "."
    elif i > prec:
      result.add s[i-1]

  result = result.reverse
  if result[0] == '.':
    result = "0" & result
  if num < 0:
    result = "-" & result

proc `<`*(a, b: Decimal): bool =
  return a.value < b.value

proc `<`*[T](a: Decimal, b: T): bool =
  return a.value < b

proc `<=`*(a, b: Decimal): bool =
  return not (b < a)

proc `<=`*[T](a: Decimal, b: T): bool =
  return a.value <= b

proc `+`*(a, b:Decimal): Decimal =
  let prec = max(a.prec, b.prec)
  let newA = a.toPrecision(prec)
  let newB = b.toPrecision(prec)
  result = (newA.value + newB.value, prec)

proc `-`*(a:Decimal): Decimal =
  result = (-a.value, a.prec)

proc `-`*(a, b:Decimal): Decimal =
  result = a + (-b)

proc `*`*[T](a: T, b:Decimal): Decimal =
  result = (a*b.value, b.prec)

proc `*`*(a, b:Decimal): Decimal =
  result = (a.value*b.value, a.prec + b.prec)

proc `==`*(a, b: Decimal): bool =
  let prec = max(a.prec, b.prec)
  let newA = a.toPrecision(prec)
  let newB = b.toPrecision(prec)
  result = newA.value == newB.value and newA.prec == newB.prec

proc inv*(a: Decimal): Decimal =
  let factors = [1, 10, 100, 1000, 10_000, 100_000, 1_000_000, 10_000_000]
  var
    mult: int64
    value: int64
    prec: int8
  if a < 1:
    mult = factors[2*a.prec].int64
    value = (mult div a.value)
    prec = a.prec

  else:
    for i, x in factors.pairs:
      if x > a.value:
        let index = min(7, i+1+a.prec)
        mult = factors[index].int64
        value = (mult div a.value)
        prec = index.int8 - a.prec
        break
  result = (value, prec)
