local root = fs.getDir(debug.getinfo(1, "S").source:sub(2))

local loaded = {}
local function relRequire(name)
  if loaded[name] == nil then
    if name:sub(1,2) == "@/" then
      fname = fs.combine(root, name:sub(3))

      loaded[name] = loadfile(fname, "bt", setmetatable({ require = relRequire }, { __index = _ENV })) ()
    end
  end

  return loaded[name]
end

local module = {}
module.__index = module

module.Writer = relRequire "@/writer.lua"
module.Reader = relRequire "@/reader.lua"
module.tools  = relRequire "@/tools.lua"
module.argutils = relRequire "@/argutils.lua"

function module:__call(...)
  local names = { ... }

  for i = 1, #names do
    names[i] = self[names[i]]
  end

  return table.unpack(names)
end

return setmetatable({}, module)
