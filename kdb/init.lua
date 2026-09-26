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

function KDB:_seek_at(o)
  self.fd:seek("set", o)
end

function KDB:_initialize_db()
  self.fd:seek("set", 0)
  self:_clear_page()

  self:_write_header {
    sections = 0,
    free_pages_root = 32,
    datas_root = 0
  }

  self:_seek_at(self.free_pages_root)
  self:_write_node {
    left_offset = 0,
    right_offset = 0,
    value_offset = self.free_pages_root + 16,
    key_size = 1024 - self.free_pages_root
  }
end

---@param header {
---  version: { major: integer; minor: integer;  };
---  sections: integer;
---  free_pages_root: integer;
---  datas_root: integer;
---}
function KDB:_write_header(header)
  local curr = self.fd:seek("cur", 0)

  self.fd:seek("set", 0)
  self.fd:write("\x01KDB")
  self.fd:write_u32(self.version.major, 2)
  self.fd:write_u32(self.version.minor, 2)

  self.sections = header.sections
  self.fd:write_u32(self.sections, 4)

  self.free_pages_root = header.free_pages_root
  self.fd:write_u32(self.free_pages_root, 4)

  self.datas_root = header.datas_root
  self.fd:write_u32(self.datas_root, 4)

  self.fd:seek("set", curr)
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

  self:_write_header {
    sections = self.sections,
    datas_root = self.datas_root,
    free_pages_root = self.free_pages_root,
    version = self.version
  }
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
    if n == nil then break end
    result.left_offset = n

    n = self.fd:read_u32(4)
    if n == nil then break end
    result.right_offset = n

    n = self.fd:read_u32(4)
    if n == nil then break end
    result.value_offset = n

    n = self.fd:read_u32(4)
    if n == nil then break end
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

  return data
end

---@alias kdb.CompareFn fun(offset: integer, node: kdb.Node): -1 | 0 | 1

---@return kdb.CompareFn
local function isLessFreeNode(xo, xw)
  return function(_, node)
    if xw < node.key_size then
      return -1
    elseif xw > node.key_size then
      return 1
    end

    if xo < node.value_offset then
      return -1
    elseif xo > node.value_offset then
      return 1
    else
      return 0
    end
  end
end

---@param key string
---@return kdb.CompareFn
local function isLessDataNode(buf, key)
  return function(offset, node)
    local mn = math.min(#key, node.key_size)

    local y = Buffer.read_at(buf, offset + 16, mn)
    if y == nil then
      error(
        ("[kdb::isLessDataNode] failed to load node key (offset: %s, size: %s)")
        :format(offset + 16, mn)
      )
    end

    for i = 1, mn do
      local a, b = key:sub(i,i), y:sub(i,i)
      if a < b then
        return -1
      elseif a > b then
        return 1
      end
    end

    if #key < node.key_size then
      return -1
    elseif #key > node.key_size then
      return 1
    else
      return 0
    end
  end
end

---@alias kdb.NextFn<R> fun(target_offset: integer, target_node: kdb.Node, dir: -1 | 0 | 1, parent_offset: integer|nil, parent_dir: -1 | 0 | 1): R
---@generic R
---@param target integer
---@param cmp kdb.CompareFn
---@param next kdb.NextFn<R>
---@param curr integer|nil
---@param parent integer|nil
---@param parent_dir -1|0|1|nil
---@return R
function KDB:_find_node(target, cmp, next, curr, parent, parent_dir)
  if curr == nil then
    curr = self.fd:seek("cur", 0)
  end

  local node = nil
  if target > 0 then
    self:_seek_at(target)
    node = self:_read_node()
  end

  if node == nil then
    error(
      ("[kdb._find_node] failed to read target node (node: %s)")
      :format(self.free_pages_root)
    )
  end

  local dir = cmp(target, node)

  if dir < 0 then
    if node.left_offset > 0 then
      return self:_find_node(node.left_offset, cmp, next, curr, target, dir)
    end

    self.fd:seek("set", curr)

    return next(target, node, dir, parent, parent_dir or 0)
  elseif dir == 0 then
    self.fd:seek("set", curr)

    return next(target, node, dir, parent, parent_dir or 0)
  else
    if node.right_offset > 0 then
      return self:_find_node(node.right_offset, cmp, next, curr, target, dir)
    end

    self.fd:seek("set", curr)

    return next(target, node, dir, parent, parent_dir or 0)
  end
end

function KDB:_allocate_page(n)
  local curr = self.fd:seek("cur", 0)

  for i = 1, n do
    self.fd:seek("set", (self.sections + i) * 1024)
    self:_clear_page()
  end

  local start = self.sections + 1
  local tail = self.sections + n
  self.sections = tail

  self.fd:seek("set", curr)

  return start, tail
end

function KDB:_allocate_space(size, target, curr)
  target = target or self.free_pages_root
  curr = curr or self.fd:seek("cur", 0)

  local node = nil
  if target > 0 then
    self:_seek_at(target)
    node = self:_read_node()
  end

  if node == nil then
    local start, tail = self:_allocate_page(math.floor((size + 1023) / 1024))
    local o, s = start * 256 * 4, (tail - start) * 256 * 4

    self:_seek_at(o)
    node = self:_write_node {
      left_offset = 0,
      right_offset = 0,
      value_offset = o + 16,
      key_size = size
    }

    target = self:_find_node(
      self.free_pages_root,
      isLessFreeNode(o + 16, s),
      function(target_offset, target_node, dir)
        if dir == 0 then
          error(
            ("[kdb.allocate_space] duplicated free space (offset: %s, size: %s)")
            :format(o + 16, s)
          )
        elseif dir < 0 then
          self:_seek_at(target_offset)
          self:_write_node {
            left_offset = o,
            right_offset = target_node.right_offset,
            value_offset = target_node.value_offset,
            key_size = target_node.key_size
          }
        else
          self:_seek_at(target_offset)
          self:_write_node {
            left_offset = target_node.left_offset,
            right_offset = o,
            value_offset = target_node.value_offset,
            key_size = target_node.key_size
          }
        end

        return target_offset
      end
    )
  end

  if size <= node.key_size then
    local rem = node.key_size - size
    if rem > 0 then
      self:_seek_at(target)
      self:_write_node {
        left_offset = node.left_offset,
        right_offset = node.right_offset,
        value_offset = node.value_offset + size,
        key_size = rem
      }
    end

    self.fd:seek("set", curr)

    return node.value_offset, size
  else
    return self:_allocate_space(size, node.right_offset, curr)
  end
end

function KDB:_create_data_node(key, value_offset)
  local node_offset, _ = self:_allocate_space(16 + #key)

  self:_seek_at(node_offset)
  self:_write_node {
    key_size = #key,
    left_offset = 0,
    right_offset = 0,
    value_offset = value_offset
  }

  self:_seek_at(node_offset + 16)
  self.fd:write(key)

  return node_offset
end

function KDB:_create_data_value(value)
  local value_offset, _ = self:_allocate_space(4 + #value)

  self:_seek_at(value_offset)
  self:_write_data_header(#value)
  self.fd:write(value)

  return value_offset
end

function KDB:_read_data_header()
  local size = self.fd:read_u32(4)

  return size
end

function KDB:_write_data_header(n)
  self.fd:write_u32(n, 4)
end

function KDB:put(key, value)
  if self.datas_root == 0 then
    self.datas_root = self:_create_data_node(key, self:_create_data_value(value))
    self:_write_header (self)

    return self.datas_root
  end

  return self:_find_node(
    self.datas_root,
    isLessDataNode(self.fd, key),
    function(target_offset, target_node, dir, parent_offset, parent_dir)
      if dir == 0 then
        self:_seek_at(target_node.value_offset)
        local value_size = self:_read_data_header()
        if #value == value_size then
          self.fd:write(value)

          return target_offset
        else
          local value_offset = self:_create_data_value(value)

          self:_seek_at(target_offset)
          self:_write_node {
            left_offset = target_node.left_offset,
            right_offset = target_node.right_offset,
            key_size = target_node.key_size,
            value_offset = value_offset
          }
        end

        return target_offset
      end

      local node_offset = self:_create_data_node(key, self:_create_data_value(value))
      if dir < 0 then
        self:_seek_at(target_offset)
        self:_write_node {
          left_offset = node_offset,
          right_offset = target_node.right_offset,
          key_size = target_node.key_size,
          value_offset = target_node.value_offset
        }
      else
        self:_seek_at(target_offset)
        self:_write_node {
          left_offset = target_node.left_offset,
          right_offset = node_offset,
          key_size = target_node.key_size,
          value_offset = target_node.value_offset
        }
      end

      return node_offset
    end
  )
end

function KDB:close()
  self.fd:close()
end

return KDB
