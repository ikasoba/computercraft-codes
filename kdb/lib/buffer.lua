local require = require "cmod" (...)
local binary = require "binary"

---@class kdb.lib.buffer.Buffer
local Buffer = {}
Buffer.__index = Buffer

function Buffer:new()
  self = setmetatable({}, Buffer)

  return self
end

---@param whence "set" | "cur" | "end"
---@param n integer
---@return number
function Buffer:seek(whence, n) return 0 end

function Buffer:size() return 0 end

---@param b string
function Buffer:write(b) end

---@param w integer
---@return string | nil
function Buffer:read(w) end

function Buffer:close() end

---@param n integer
---@param w integer
function Buffer:write_u32(n, w)
  return self:write(binary.encode_u32(n):sub(1,w))
end

---@param w integer
---@return integer | nil
function Buffer:read_u32(w)
  local b = self:read(w)
  if b == nil then
    return nil
  end

  return binary.decode_u32(b)
end

return Buffer
