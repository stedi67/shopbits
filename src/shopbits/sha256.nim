## SHA-256, to give data a content-derived identity.
##
## The standard library's sha1 and md5 are deprecated in favor of the external
## `checksums` package. This small implementation avoids a dependency for the one
## thing needed here. It is checked against the published test vectors.

const
  K = [
    0x428a2f98'u32, 0x71374491'u32, 0xb5c0fbcf'u32, 0xe9b5dba5'u32, 0x3956c25b'u32,
    0x59f111f1'u32, 0x923f82a4'u32, 0xab1c5ed5'u32, 0xd807aa98'u32, 0x12835b01'u32,
    0x243185be'u32, 0x550c7dc3'u32, 0x72be5d74'u32, 0x80deb1fe'u32, 0x9bdc06a7'u32,
    0xc19bf174'u32, 0xe49b69c1'u32, 0xefbe4786'u32, 0x0fc19dc6'u32, 0x240ca1cc'u32,
    0x2de92c6f'u32, 0x4a7484aa'u32, 0x5cb0a9dc'u32, 0x76f988da'u32, 0x983e5152'u32,
    0xa831c66d'u32, 0xb00327c8'u32, 0xbf597fc7'u32, 0xc6e00bf3'u32, 0xd5a79147'u32,
    0x06ca6351'u32, 0x14292967'u32, 0x27b70a85'u32, 0x2e1b2138'u32, 0x4d2c6dfc'u32,
    0x53380d13'u32, 0x650a7354'u32, 0x766a0abb'u32, 0x81c2c92e'u32, 0x92722c85'u32,
    0xa2bfe8a1'u32, 0xa81a664b'u32, 0xc24b8b70'u32, 0xc76c51a3'u32, 0xd192e819'u32,
    0xd6990624'u32, 0xf40e3585'u32, 0x106aa070'u32, 0x19a4c116'u32, 0x1e376c08'u32,
    0x2748774c'u32, 0x34b0bcb5'u32, 0x391c0cb3'u32, 0x4ed8aa4a'u32, 0x5b9cca4f'u32,
    0x682e6ff3'u32, 0x748f82ee'u32, 0x78a5636f'u32, 0x84c87814'u32, 0x8cc70208'u32,
    0x90befffa'u32, 0xa4506ceb'u32, 0xbef9a3f7'u32, 0xc67178f2'u32]

func rotr(x: uint32, n: int): uint32 = (x shr n) or (x shl (32 - n))

func compress(h: var array[8, uint32], chunk: openArray[byte]) =
  var w: array[64, uint32]
  for i in 0 ..< 16:
    w[i] = (uint32(chunk[4 * i]) shl 24) or (uint32(chunk[4 * i + 1]) shl 16) or
           (uint32(chunk[4 * i + 2]) shl 8) or uint32(chunk[4 * i + 3])
  for i in 16 ..< 64:
    let
      s0 = rotr(w[i - 15], 7) xor rotr(w[i - 15], 18) xor (w[i - 15] shr 3)
      s1 = rotr(w[i - 2], 17) xor rotr(w[i - 2], 19) xor (w[i - 2] shr 10)
    w[i] = w[i - 16] + s0 + w[i - 7] + s1
  var v = h
  for i in 0 ..< 64:
    let
      s1 = rotr(v[4], 6) xor rotr(v[4], 11) xor rotr(v[4], 25)
      ch = (v[4] and v[5]) xor ((not v[4]) and v[6])
      t1 = v[7] + s1 + ch + K[i] + w[i]
      s0 = rotr(v[0], 2) xor rotr(v[0], 13) xor rotr(v[0], 22)
      maj = (v[0] and v[1]) xor (v[0] and v[2]) xor (v[1] and v[2])
      t2 = s0 + maj
    v[7] = v[6]; v[6] = v[5]; v[5] = v[4]; v[4] = v[3] + t1
    v[3] = v[2]; v[2] = v[1]; v[1] = v[0]; v[0] = t1 + t2
  for i in 0 ..< 8:
    h[i] = h[i] + v[i]

func sha256Hex*(data: string): string =
  ## The SHA-256 of `data` as 64 lower case hex digits.
  var h = [0x6a09e667'u32, 0xbb67ae85'u32, 0x3c6ef372'u32, 0xa54ff53a'u32,
           0x510e527f'u32, 0x9b05688c'u32, 0x1f83d9ab'u32, 0x5be0cd19'u32]
  # the message, a 1 bit, zeros, and the length in bits as 64 bit big endian
  var message = newSeq[byte](data.len)
  for i, c in data: message[i] = byte(c)
  message.add 0x80'u8
  while message.len mod 64 != 56: message.add 0'u8
  let bits = uint64(data.len) * 8
  for i in countdown(7, 0): message.add byte((bits shr (i * 8)) and 0xff)
  for start in countup(0, message.len - 64, 64):
    compress(h, message.toOpenArray(start, start + 63))
  const digits = "0123456789abcdef"
  for word in h:
    for i in countdown(7, 0):
      result.add digits[int((word shr (i * 4)) and 0xf)]
