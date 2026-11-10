import std/[unittest, strutils]
import shopbits/sha256

suite "sha256":
  test "the published test vectors":
    check sha256Hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    check sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    check sha256Hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") ==
      "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
    check sha256Hex(repeat('a', 1_000_000)) ==
      "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"

  test "lengths around the block and padding boundaries":
    check sha256Hex(repeat('a', 55)) == "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318"
    check sha256Hex(repeat('a', 56)) == "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a"
    check sha256Hex(repeat('a', 57)) == "f13b2d724659eb3bf47f2dd6af1accc87b81f09f59f2b75e5c0bed6589dfe8c6"
    check sha256Hex(repeat('a', 63)) == "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34"
    check sha256Hex(repeat('a', 64)) == "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"
    check sha256Hex(repeat('a', 65)) == "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0"
    check sha256Hex(repeat('a', 119)) == "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb"
    check sha256Hex(repeat('a', 120)) == "2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c"
    check sha256Hex(repeat('a', 128)) == "6836cf13bac400e9105071cd6af47084dfacad4e5e302c94bfed24e013afb73e"

  test "bytes are hashed, not characters":
    check sha256Hex("grüße, €100 ✓") == "10467481da49cb74ad154d5a762477f9bfd72ee9b4fe5057e124afea354a3963"

  test "the result is 64 lower case hex digits":
    let h = sha256Hex("anything")
    check h.len == 64
    check h == h.toLowerAscii
    for c in h: check c in {'0'..'9', 'a'..'f'}

  test "different data gives different hashes":
    check sha256Hex("a") != sha256Hex("b")
    check sha256Hex("ab") != sha256Hex("ba")
