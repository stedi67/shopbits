import std/[unittest, options]
import shopbits/date

suite "dates":
  test "a valid date":
    let d = initDate(2026, 2, 28)
    check d.year == 2026 and d.month == 2 and d.day == 28
    check $d == "2026-02-28"

  test "invalid dates are rejected":
    expect ValueError: discard initDate(2026, 2, 29)   # not a leap year
    expect ValueError: discard initDate(2026, 13, 1)
    expect ValueError: discard initDate(2026, 0, 1)
    expect ValueError: discard initDate(2026, 4, 31)
    expect ValueError: discard initDate(2026, 1, 0)
    expect ValueError: discard initDate(0, 1, 1)

  test "leap years":
    check isValidDate(2024, 2, 29)
    check not isValidDate(2100, 2, 29)  # divisible by 100, not by 400
    check isValidDate(2000, 2, 29)      # divisible by 400

  test "dates compare chronologically":
    check initDate(2026, 12, 31) < initDate(2027, 1, 1)
    check initDate(2026, 1, 31) < initDate(2026, 2, 1)
    check initDate(2026, 3, 9) < initDate(2026, 3, 10)
    check initDate(2026, 3, 10) <= initDate(2026, 3, 10)
    check initDate(2026, 3, 10) == initDate(2026, 3, 10)
    check not (initDate(2027, 1, 1) < initDate(2026, 12, 31))

  test "printing pads with zeros":
    check $initDate(5, 1, 2) == "0005-01-02"
    check $initDate(2026, 1, 9) == "2026-01-09"

  test "parsing is strict":
    check parseDate("2026-01-31") == initDate(2026, 1, 31)
    check tryParseDate("2026-01-31").get == initDate(2026, 1, 31)
    for bad in ["", "2026-1-31", "2026-01-3", "26-01-31", "2026/01/31", "2026-01-31 ",
                " 2026-01-31", "2026-02-30", "2026-13-01", "20260131", "abcd-ef-gh",
                "2026-01-+1", "2026-0a-10"]:
      check tryParseDate(bad).isNone
      expect ValueError: discard parseDate(bad)

  test "printing and parsing are inverse":
    for d in [initDate(1, 1, 1), initDate(2024, 2, 29), initDate(9999, 12, 31)]:
      check parseDate($d) == d

  test "today is a valid date":
    let d = today()
    check isValidDate(d.year, d.month, d.day)
