local require = require "cmod" (...)
local binary = require "lib.binary"
local Buffer = require "lib.buffer"

---@alias kdb.CompareFn fun(offset: integer, node: kdb.Node): -1 | 0 | 1

---@param xo integer|nil
---@param xw integer
---@return kdb.CompareFn
local function isLessFreeNode(xo, xw)
  return function(_, node)
    if xw < node.key_size then
      return -1
    elseif xw > node.key_size then
      return 1
    end

    if xo == nil then
      return 0
    elseif xo < node.value_offset then
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
      local a, b = key:sub(i, i), y:sub(i, i)
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

---@class kdb.KDB
local KDB = {}
KDB.__index = KDB

KDB.version = { major = 0, minor = 0 }

---@param file kdb.lib.buffer.Buffer
function KDB:new(file)
  self = setmetatable({}, KDB)

  self.fd = file
  self.is_ready = false

  self._lessFreeDataNodeFactory = function(offset)
    self:_seek_at(offset)
    local node = self:_read_node()
    if node == nil then
      error(
        ("[KDB._lessFreeDataNodeFactory] failed to load target node (offset: %s)"):format(offset)
      )
    end

    return isLessFreeNode(node.value_offset, node.key_size)
  end

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
    key_size = 1024 - self.free_pages_root - 16
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

---@alias kdb.FindResult {
---  target_offset: integer;
---  target_node: kdb.Node;
---  dir: -1 | 0 | 1;
---  parent_offset: integer | nil;
---  parent_dir: -1 | 0 | 1;
---}
---@param target integer
---@param cmp kdb.CompareFn
---@param curr integer|nil
---@param parent integer|nil
---@param parent_dir -1|0|1|nil
---@return kdb.FindResult
function KDB:_find_node(target, cmp, curr, parent, parent_dir)
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
      :format(target)
    )
  end

  local dir = cmp(target, node)
  if dir < 0 then
    if node.left_offset > 0 then
      return self:_find_node(node.left_offset, cmp, curr, target, dir)
    end
  elseif dir == 0 then
    --
  else
    if node.right_offset > 0 then
      return self:_find_node(node.right_offset, cmp, curr, target, dir)
    end
  end

  self.fd:seek("set", curr)

  return {
    target_offset = target,
    target_node = node,
    dir = dir,
    parent_offset = parent,
    parent_dir = parent_dir or 0
  }
end

---@param target integer
---@param size integer
---@param curr integer|nil
---@param parent integer|nil
---@param ...integer|nil
function KDB:_find_allocatable_node(target, size, curr, parent)
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
      ("[kdb._find_allocatable_node] failed to read target node (node: %s)")
      :format(target)
    )
  end

  if node.left_offset > 0 then
    local left = nil
    self:_seek_at(node.left_offset)
    left = self:_read_node()

    if left == nil then
      error(
        ("[kdb._find_allocatable_node] failed to read target left node (left: %s)")
        :format(node.left_offset)
      )
    end

    if size < left.key_size then
      return self:_find_allocatable_node(node.left_offset, size, curr, target)
    end
  end

  if size < node.key_size then
    self.fd:seek("set", curr)

    return {
      target_offset = target,
      target_node = node,
      parent_offset = parent
    }
  end

  if node.right_offset > 0 then
    local right = nil
    self:_seek_at(node.right_offset)
    right = self:_read_node()

    if right == nil then
      error(
        ("[kdb._find_allocatable_node] failed to read target right node (right: %s)")
        :format(node.right_offset)
      )
    end

    if size < right.key_size then
      return self:_find_allocatable_node(node.right_offset, size, curr, target)
    end
  end

  return nil
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
  self:_write_header(self)

  self.fd:seek("set", curr)

  return start, tail
end

---@param target_offset integer
---@param parent_offset integer
---@param root_offset integer
---@param getComparator fun(offset: integer): kdb.CompareFn
---@return nil
function KDB:_insert_node(target_offset, parent_offset, root_offset, getComparator)
  local findResult = self:_find_node(parent_offset, getComparator(target_offset))
  if findResult.dir == 0 then
    error(
      ("[kdb:_insert_node] node insertion conflicted (node_offset: %s, tree_offset: %s)")
      :format(target_offset, parent_offset)
    )
  elseif findResult.dir < 0 then
    local tl = findResult.target_node.left_offset
    findResult.target_node.left_offset = target_offset

    self:_seek_at(findResult.target_offset)
    self:_write_node(findResult.target_node)

    if tl > 0 then
      return self:_insert_node(tl, root_offset, root_offset, getComparator)
    end
  else
    local tr = findResult.target_node.right_offset
    findResult.target_node.right_offset = target_offset

    self:_seek_at(findResult.target_offset)
    self:_write_node(findResult.target_node)

    if tr > 0 then
      return self:_insert_node(tr, root_offset, root_offset, getComparator)
    end
  end
end

---@param target_offset integer
function KDB:_free_data_node(target_offset)
  self:_seek_at(target_offset)
  local node = self:_read_node()
  if node == nil then
    error(("[KDB:_free_data_node] failed to read target node (offset: %s)"):format(target_offset))
  end

  node.value_offset = target_offset
  node.key_size = node.key_size + 16
  node.left_offset = 0
  node.right_offset = 0

  self:_seek_at(target_offset)
  self:_write_node(node)

  self:_insert_node(target_offset, self.free_pages_root, self.free_pages_root, self._lessFreeDataNodeFactory)
end

function KDB:_remove_space_node(target_offset, parent_offset, target_node, parent_node)
  if target_node == nil then
    self:_seek_at(target_offset)
    target_node = self:_read_node()
  end

  if target_node == nil then
    error(("[KDB:_free_data_node] failed to read target node (offset: %s)"):format(target_offset))
  end

  if parent_offset == nil then
    if self.free_pages_root ~= nil and target_offset ~= self.free_pages_root then
      error(("[KDB:_free_data_node] target node is not root node (offset: %s)"):format(target_offset))
    end

    local left_offset, right_offset = target_node.left_offset, target_node.right_offset
    target_node.left_offset = 0
    target_node.right_offset = 0

    self:_seek_at(target_offset)
    self:_write_node(target_node)

    if left_offset > 0 then
      if self.free_pages_root == nil then
        self.free_pages_root = left_offset
      else
        self:_insert_node(left_offset, self.free_pages_root, self.free_pages_root, self._lessFreeDataNodeFactory)
      end
    end

    if right_offset > 0 then
      if self.free_pages_root == nil then
        self.free_pages_root = right_offset
      else
        self:_insert_node(right_offset, self.free_pages_root, self.free_pages_root, self
          ._lessFreeDataNodeFactory)
      end
    end
  else
    if parent_node == nil then
      self:_seek_at(parent_offset)
      parent_node = self:_read_node()
    end

    if parent_node == nil then
      error(("[KDB:_free_data_node] failed to read parent node (offset: %s)"):format(parent_offset))
    end

    if parent_node.left_offset == target_offset then
      parent_node.left_offset = 0
    elseif parent_node.right_offset == target_offset then
      parent_node.right_offset = 0
    else
      error(("[KDB:_free_data_node] target node is not children (target_offset: %s, parent_offset: %s)"):format(
        target_offset, parent_offset))
    end

    self:_seek_at(parent_offset)
    self:_write_node(parent_node)

    local left_offset, right_offset = target_node.left_offset, target_node.right_offset
    target_node.left_offset = 0
    target_node.right_offset = 0

    self:_seek_at(target_offset)
    self:_write_node(target_node)

    if left_offset > 0 then
      self:_insert_node(left_offset, self.free_pages_root, self.free_pages_root, self._lessFreeDataNodeFactory)
    end

    if right_offset > 0 then
      self:_insert_node(right_offset, self.free_pages_root, self.free_pages_root, self
        ._lessFreeDataNodeFactory)
    end
  end

  return target_offset
end

function KDB:_allocate_space(size, target, curr, loop_count)
  loop_count = (loop_count or 0) + 1
  if loop_count > 32 then
    error(("[KDB:_allocate_space] allocation loop detected (loop_count: %s)"):format(loop_count))
  end
  
  target = target or self.free_pages_root
  curr = curr or self.fd:seek("cur", 0)

  local findResult = self:_find_allocatable_node(
    target,
    size
  )

  if findResult ~= nil then
    local rem = findResult.target_node.key_size - size
    if rem > 0 then
      self:_remove_space_node(findResult.target_offset, findResult.parent_offset, findResult.target_node)

      local value_offset = findResult.target_node.value_offset
      if value_offset == findResult.target_offset then
        if rem <= 0 then
          error("ERROR")
        end

        self:_seek_at(findResult.target_offset)
        self:_write_node {
          left_offset = 0,
          right_offset = 0,
          value_offset = value_offset,
          key_size = rem
        }

        value_offset = value_offset + 16 + rem
      else
        self:_seek_at(findResult.target_offset)
        self:_write_node {
          left_offset = 0,
          right_offset = 0,
          value_offset = value_offset,
          key_size = rem
        }

        value_offset = value_offset + rem
      end

      if findResult.target_offset ~= self.free_pages_root then
        self:_insert_node(findResult.target_offset, self.free_pages_root, self.free_pages_root,
          self._lessFreeDataNodeFactory)
      end

      self.fd:seek("set", curr)

      return value_offset
    elseif rem == 0 then
      local value_offset = findResult.target_node.value_offset
      self:_remove_space_node(findResult.target_offset, findResult.parent_offset, findResult.target_node)

      self:_seek_at(findResult.target_offset)
      self:_write_node {
        left_offset = 0,
        right_offset = 0,
        value_offset = findResult.target_offset,
        key_size = 16
      }

      if findResult.target_offset ~= self.free_pages_root then
        self:_insert_node(findResult.target_offset, self.free_pages_root, self.free_pages_root,
          self._lessFreeDataNodeFactory)
      end

      self.fd:seek("set", curr)

      return value_offset
    end
  end

  -- tarinai no naraba aratashii page wo kakuho

  local start, tail = self:_allocate_page(math.floor((size + 1023 + 16) / 1024))
  local o, s = start * 256 * 4, (tail - start + 1) * 256 * 4

  self:_seek_at(o)
  self:_write_node {
    left_offset = 0,
    right_offset = 0,
    value_offset = o + 16,
    key_size = s - 16
  }

  if o ~= self.free_pages_root then
    self:_insert_node(o, self.free_pages_root, self.free_pages_root, self._lessFreeDataNodeFactory)
  end

  -- mokkai yaru

  return self:_allocate_space(size, nil, curr, loop_count)
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
    self:_write_header(self)

    return self.datas_root
  end

  local findResult = self:_find_node(
    self.datas_root,
    isLessDataNode(self.fd, key)
  )

  if findResult.dir == 0 then
    self:_seek_at(findResult.target_node.value_offset)
    local value_size = self:_read_data_header()
    if #value == value_size then
      self.fd:write(value)

      return findResult.target_offset
    else
      local value_offset = self:_create_data_value(value)

      self:_seek_at(findResult.target_offset)
      self:_write_node {
        left_offset = findResult.target_node.left_offset,
        right_offset = findResult.target_node.right_offset,
        key_size = findResult.target_node.key_size,
        value_offset = value_offset
      }
    end

    return findResult.target_offset
  end

  local node_offset = self:_create_data_node(key, self:_create_data_value(value))
  if findResult.dir < 0 then
    self:_seek_at(findResult.target_offset)
    self:_write_node {
      left_offset = node_offset,
      right_offset = findResult.target_node.right_offset,
      key_size = findResult.target_node.key_size,
      value_offset = findResult.target_node.value_offset
    }
  else
    self:_seek_at(findResult.target_offset)
    self:_write_node {
      left_offset = findResult.target_node.left_offset,
      right_offset = node_offset,
      key_size = findResult.target_node.key_size,
      value_offset = findResult.target_node.value_offset
    }
  end

  return node_offset
end

function KDB:get(...)
  if self.datas_root == 0 then
    return
  end

  local results = {}
  local n = select("#", ...)

  for i = 1, n do
    local findResult = self:_find_node(
      self.datas_root,
      isLessDataNode(self.fd, (select(i, ...)))
    )

    if findResult.dir == 0 then
      results[i] = findResult.target_node.value_offset
    end
  end

  for i = 1, n do
    local offset = results[i]
    if offset ~= nil then
      self:_seek_at(offset)
      local size = self:_read_data_header()
      if size == nil then
        error(("[KDB:get] failed to load value section (value_offset: %s, size: %s)"):format(offset, size))
      end

      results[i] = self.fd:read(size)
    else
      results[i] = nil
    end
  end

  return n, table.unpack(results, 1, n)
end

function KDB:close()
  self.fd:close()
end

return KDB
