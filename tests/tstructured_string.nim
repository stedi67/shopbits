import unittest
import shopcore/structured_string

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

suite "structured_string":
  test "fields are slices of the string":
    let foo = newTest("aaaaabbbbb")
    check foo.a == "aaaaa"
    check foo.b == "bbbbb"

  test "constructor checks the length":
    expect ValueError:
      discard newTest("too short")
