#!/usr/bin/env nimdebug
#
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

macro StructuredString(name: untyped, deflist: untyped): untyped =
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

when isMainModule:
  StructuredString(test):
    a:5
    b:5

  StructuredString(SoftwareArticleCode):
    product_id:4
    version:2
    channel:2
    right:2
    required_product:4
    rop:2
    delivery:2
    num_instances:1
    serial_number_type:1
    language:2
    customer_group_discount:2
    license_dependent_discount:2

  var foo = newTest("aaaaabbbbb")
  echo "running assetions"
  assert foo.a == "aaaaa"
  assert foo.b == "bbbbb"
