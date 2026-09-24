local require = require "cmod" (...)
local binary = require "lib.binary"
local Buffer = require "lib.buffer"

---@class kdb.KDB
local KDB = {}
KDB.__index = KDB

KDB.version = { major = 0, minor = 0 }

---@param file kdb.lib.buffer.Buffer
function KDB:new(file)
  self = setmetatable({}, KDB)

  self.fd = file
  self.is_ready = false

  return self
end

function KDB:open()
  if self.fd:seek("end", 0) == 0 then
    self:_initialize_db()
  else
    self:_resume_db()
  end
end

--- fill zeros 256 * 4 byte
function KDB:_clear_page()
  local curr = self.fd:seek("cur", 0)
  for _ = 1, 256 do
    self.fd:write_u32(0, 4)
  end

  self.fd:seek("set", curr)
end

function KDB:_seek_element(o)
  self.fd:seek("set", o*4)
end

function KDB:_initialize_db()
  self.fd:seek("set", 0)
  self:_clear_page()

  self.fd:write("\x01KDB")
  self.fd:write_u32(self.version.major, 2)
  self.fd:write_u32(self.version.minor, 2)

  self.sections = 0
  self.fd:write_u32(self.sections, 4)

  self.free_pages_root = 7
  self.fd:write_u32(self.free_pages_root, 4)

  self.datas_root = 0
  self.fd:write_u32(self.datas_root, 4)

  self:_seek_element(self.free_pages_root)
  self:_write_node {
    left_offset = 0,
    right_offset = 0,
    value_offset = self.free_pages_root,
    key_size = 256-self.free_pages_root
  }
end

function KDB:_resume_db()
  self.fd:seek("set", 0)
  local top_block = self.fd:read(4)
  if top_block ~= "\x01KDB" then
    error("kdb database format header is invalid.")
  end

  local major = self.fd:read_u32(2)
  local minor = self.fd:read_u32(2)

  if major ~= self.version.major then
    error(("incompatible kdb major version: (file: %s, current: %s)"):format(major, self.version.major))
  end

  if minor > self.version.minor then
    error(("incompatible kdb minor version: (file: %s, current: %s)"):format(minor, self.version.minor))
  end

  self.sections = self.fd:read_u32(4)
  self.free_pages_root = self.fd:read_u32(4)
  self.datas_root = self.fd:read_u32(4)

  self.fd:seek("set", 4)
  self.fd:write_u32(self.version.major, 2)
  self.fd:write_u32(self.version.minor, 2)
end

---@alias kdb.Node {
---  left_offset: integer;
---  right_offset: integer;
---  value_offset: integer;
---  key_size: integer;
---}

---@return kdb.Node | nil
function KDB:_read_node()
  local result = {}

  local curr = self.fd:seek("cur", 0)

  repeat
    local n = self.fd:read_u32(4)
    if n == nil then return nil end
    result.left_offset = n

    n = self.fd:read_u32(4)
    if n == nil then return nil end
    result.right_offset = n

    n = self.fd:read_u32(4)
    if n == nil then return nil end
    result.value_offset = n

    n = self.fd:read_u32(4)
    if n == nil then return nil end
    result.key_size = n

    return result
  until 1

  self.fd:seek("set", curr)

  return nil
end

---@param data kdb.Node
function KDB:_write_node(data)
  self.fd:write_u32(data.left_offset, 4)
  self.fd:write_u32(data.right_offset, 4)
  self.fd:write_u32(data.value_offset, 4)
  self.fd:write_u32(data.key_size, 4)
end

function KDB:close()
  self.fd:close()
end

return KDB
