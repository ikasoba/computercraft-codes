local binary = {}

function binary.encode_u32(n)
  return string.char (
    bit32.extract(n, 0, 8),
    bit32.extract(n, 8, 8),
    bit32.extract(n, 16, 8),
    bit32.extract(n, 24, 8)
  )
end

function binary.decode_u32(t)
  local n = 0
  for i, x in ipairs({ string.byte(t, 1, 4) }) do
    n = bit32.bor(n, bit32.lshift (x, (i-1) * 8))
  end

  return n
end

function binary.decode_i32(t)
  local n = binary.decode_u32(t)
  
  if n > 2147483647 then
    return n - 4294967296
  else
    return n
  end
end

return binary
