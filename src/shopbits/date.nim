## Calendar dates, for the effective dates of rules.
##
## A `Date` is a plain calendar day without a time or a time zone. Dates compare
## chronologically (``a < b``, ``a <= b``, ``a == b``).

import std/[options, strutils, times]

type
  Date* = tuple[year: int, month: int, day: int]

func isValidDate*(year, month, day: int): bool =
  ## Is this a real day in the calendar (e.g. no 31st of February)?
  year in 1 .. 9999 and month in 1 .. 12 and
    day in 1 .. getDaysInMonth(Month(month), year)

func initDate*(year, month, day: int): Date =
  ## Raises `ValueError` if there is no such day.
  if not isValidDate(year, month, day):
    raise newException(ValueError,
      "not a valid date: " & $year & "-" & $month & "-" & $day)
  (year, month, day)

func `$`*(date: Date): string =
  ## The ISO format, e.g. ``2026-01-31``.
  align($date.year, 4, '0') & "-" & align($date.month, 2, '0') & "-" &
    align($date.day, 2, '0')

func tryParseDate*(s: string): Option[Date] =
  ## Parses exactly the ISO format ``YYYY-MM-DD`` (digits only, with leading zeros).
  if s.len != 10 or s[4] != '-' or s[7] != '-': return none(Date)
  for i in [0, 1, 2, 3, 5, 6, 8, 9]:
    if s[i] notin {'0'..'9'}: return none(Date)
  let
    year = parseInt(s[0 .. 3])
    month = parseInt(s[5 .. 6])
    day = parseInt(s[8 .. 9])
  if isValidDate(year, month, day): some((year, month, day)) else: none(Date)

func parseDate*(s: string): Date =
  ## Like `tryParseDate`, but raises `ValueError` for anything but a valid date
  ## in the format ``YYYY-MM-DD``.
  let date = tryParseDate(s)
  if date.isNone:
    raise newException(ValueError, "'" & s & "' is not a date in the format YYYY-MM-DD")
  date.get

proc today*(): Date =
  ## The current day in the local time zone. Code that must be reproducible
  ## should be given its date instead of asking for it.
  let n = now()
  (n.year, ord(n.month), n.monthday)
