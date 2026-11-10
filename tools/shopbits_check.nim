## Checks a data directory: loads it with `shopbits/snapshot` and reports all the
## problems, or the id of the snapshot. For CI of a data repository.
##
##   nim c -r tools/shopbits_check.nim <data directory>
##
## The exit code is 0 if the data is fine, 1 if there are problems, and 2 for
## wrong usage.

import std/os
import ../src/shopbits/snapshot

when isMainModule:
  if paramCount() != 1:
    stderr.writeLine "usage: shopbits_check <data directory>"
    quit 2
  let dir = paramStr(1)
  let issues = checkSnapshot(dir)
  if issues.len > 0:
    for issue in issues:
      stderr.writeLine "error: " & $issue
    stderr.writeLine $issues.len & " problem(s) in '" & dir & "'"
    quit 1
  let data = loadSnapshot(dir)
  echo "ok: ", dir, "\n  snapshot ", data.id,
       (if data.name.len > 0: " (" & data.name & ")" else: ""),
       "\n  ", data.nexuses.len, " nexuses, ", data.ruleCount, " rules, ",
       data.files.len, " files"
