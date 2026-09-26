local FileEntryKind = {
  File = 0,
  Directory = 1
}

local function getAllFilePath(inputs)
  local stack = { table.unpack(inputs) }

  local function f()
    if #stack <= 0 then
      return
    end
       
    local name = table.remove(stack)
        
    if fs.isDir(name) then
      for _, child in ipairs(fs.list(name)) do
        table.insert(stack, fs.combine(name, child))
      end
            
      return FileEntryKind.Directory, name
    else
      return FileEntryKind.File, name
    end
  end
    
  return f
end

local function writeLiteral(dst, value)
  if type(value) == "table" then
    local isArray = true
    local prev_i = 0
    for k, v in pairs(value) do
      if type(k) ~= "number" or prev_i + 1 ~= k then
        isArray = false
      end
    end

    if isArray then
      dst:write "{ "

      for i, v in ipairs(value) do
        if i > 1 then
          dst:write ", "
        end

        dst:writeLiteral(dst, v)
      end

      dst:write " }"
    else
      dst:write "{ "

      local isFirst = true
      for k, v in pairs(value) do
        if not isFirst then
          dst:write ", "
        end

        dst:write "[ "
        dst:writeLiteral(dst, k)
        dst:write "] = "

        dst:writeLiteral(dst, v)

        isFirst = false
      end

      dst:write " }"
    end
  elseif type(value) == "string" then
    dst:write "\""

    for i = 1, #value do
      local c = value:sub(i,i)

      if c == "\"" then
        c = "\\\""
      elseif c == "\n" then
        c = "\\n"
      elseif c == "\\" then
        c = "\\\\"
      end

      dst:write (c)
    end
    
    dst:write "\""
  else
    dst:write (("%s"):format(value))
  end
end

local function main(name, ...)
  local inputs = { ... }
  
  name = shell.resolve(name)
  local dst, msg = io.open(name, "w+")

  for i = 1, #inputs do
    inputs[i] = shell.resolve(inputs[i])
  end

  local cwd = shell.resolve(".")

  dst:write("local function mkdir(p) p = shell.resolve(p); if not fs.exists(p) then fs.makeDir(p) end end\n")
  dst:write("local function writeFile(p,body) p = shell.resolve(p); local f = io.open(p, \"w+\"); f:write(body); f:close() end\n")
  
  for kind, fname in getAllFilePath(inputs) do
    local relname = fname:sub(#cwd+2)
    if fname ~= name and relname:sub(1,1) ~= "." then    
      if kind == FileEntryKind.Directory then
        dst:write("mkdir(")
        writeLiteral (dst, fname:sub(#cwd+2))
        dst:write(")\n")
      else
        dst:write("writeFile(")
        writeLiteral (dst, fname:sub(#cwd+2))
        dst:write(", ")

        local f = fs.open (fname, "r")
        writeLiteral (dst, f.readAll())
        f.close()
        
        dst:write(")\n")
      end
    end
  end

  dst:close()
end

main (table.unpack(arg))
