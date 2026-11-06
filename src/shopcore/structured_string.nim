import macros, strutils

const newFuncText = """
proc new$2(text:string):$1 =
  if text.len != $3:
    var e:ref ValueError
    new(e)
    e.msg = "A new $2 needs to have length $3"
    raise e
  result = $1(text)
"""

macro StructuredString*(name: untyped, deflist: untyped): untyped =
  var
    low:BiggestInt = 0
    high:BiggestInt = 0
    fieldName: string
    fieldLen: BiggestInt
    typeName = name.strVal

  result = newStmtList()
  result.add(parseStmt("type $1 = string" % typeName))
  for i in 0..deflist.len-1:
    fieldName = deflist[i][0].strVal
    fieldLen = deflist[i][1][0].intVal
    high = high + fieldLen
    result.add(parseStmt("proc $#(base:$#): string = result = base[$#..$#]" % [fieldName, typeName, $low, $(high-1)]))
    low = low + fieldLen
  result.add(parseStmt(newFuncText % [typeName, typeName.capitalizeAscii, $high]))
