local xxhash = {}

local function imul32(a, b)
  local al = bit32.band(a, 0xFFFF)
  local au = bit32.rshift(a, 16)

  local bl = bit32.band(b, 0xFFFF)
  local bu = bit32.rshift(b, 16)

  return bit32.band(
    (al * bl) + (au * bl + al * bu) * 0x10000,
    0xFFFFFFFF
  )
end

local function decodeU32L(t, n)
  n = n or 1
  local a, b, c, d = string.byte(t, n, n + 3)
  a = a or 0
  b = b or 0
  c = c or 0
  d = d or 0

  return bit32.bor(a, b * 256, c * 65536, d * 16777216)
end

local PRIME32_1 = 0x9E3779B1
local PRIME32_2 = 0x85EBCA77
local PRIME32_3 = 0xC2B2AE3D
local PRIME32_4 = 0x27D4EB2F
local PRIME32_5 = 0x165667B1

---@return ...integer
local function digest32_step2(t, i, acc, ...)
  if acc == nil then
    return
  end

  local lane = decodeU32L(t, i)

  acc = acc + imul32(lane, PRIME32_2)
  acc = bit32.lrotate(acc, 13)
  acc = imul32(acc, PRIME32_1)

  return acc, digest32_step2(t, i + 4, ...)
end

---@return ...integer
local function digest32_step5_6(t_rem, acc)
  local n = #t_rem
  local m = 1

  while n >= 4 do
    local lane = decodeU32L(t_rem, m)

    acc = acc + imul32(lane, PRIME32_3)
    acc = imul32(bit32.lrotate(acc, 17), PRIME32_4)

    m = m + 4
    n = n - 4
  end

  while n >= 1 do
    local lane = string.byte(t_rem, m)

    acc = acc + imul32(lane, PRIME32_5)
    acc = imul32(bit32.lrotate(acc, 11), PRIME32_1)

    m = m + 1
    n = n - 1
  end

  acc = bit32.bxor(acc, bit32.rshift(acc, 15))
  acc = imul32(acc, PRIME32_2)
  acc = bit32.bxor(acc, bit32.rshift(acc, 13))
  acc = imul32(acc, PRIME32_3)
  acc = bit32.bxor(acc, bit32.rshift(acc, 16))

  return acc
end

---@param seed integer | nil
local function digest32_step1_4(t, seed)
  local acc1 = seed + PRIME32_1 + PRIME32_2
  local acc2 = seed + PRIME32_2
  local acc3 = seed
  local acc4 = seed - PRIME32_1

  local n = math.floor(#t / 16) * 16
  for i = 1, n, 16 do
    acc1, acc2, acc3, acc4 = digest32_step2(t, i, acc1, acc2, acc3, acc4)
  end

  local acc =
      bit32.lrotate(acc1, 1)
    + bit32.lrotate(acc2, 7)
    + bit32.lrotate(acc3, 12)
    + bit32.lrotate(acc4, 18)

  acc = acc + #t

  return digest32_step5_6(t:sub(n+1), acc)
end

local function digest32_under16(t, seed)
  local acc = seed + PRIME32_5
  acc = acc + #t

  return digest32_step5_6(t, acc)
end

---@param t string
---@param seed integer|nil
---@return integer
function xxhash.digest32(t, seed)
  seed = seed or 0

  if #t < 16 then
    return digest32_under16(t, seed)
  else
    return digest32_step1_4(t, seed)
  end
end

return xxhash
