## Verifies a cart against a data directory: reads a request (JSON) from a file or
## from standard input and prints the result (JSON). See `shopbits/verify` for the
## formats.
##
##   nim c -r tools/shopbits_verify.nim <data directory> [request.json]
##
## The exit code is 0 for a result, 1 if the request is malformed (the errors are
## printed), 2 for wrong usage and 3 if the data has problems.

import std/[json, os]
import ../src/shopbits/[snapshot, verify]

when isMainModule:
  if paramCount() notin 1 .. 2:
    stderr.writeLine "usage: shopbits_verify <data directory> [request.json]"
    quit 2
  let issues = checkSnapshot(paramStr(1))
  if issues.len > 0:
    for issue in issues:
      stderr.writeLine "error: " & $issue
    quit 3
  let data = loadSnapshot(paramStr(1))
  let request =
    if paramCount() == 2 and paramStr(2) != "-": readFile(paramStr(2))
    else: stdin.readAll()
  let response = data.verifyText(request)
  echo response.body.pretty
  quit(if response.ok: 0 else: 1)
