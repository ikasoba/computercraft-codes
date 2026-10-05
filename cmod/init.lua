local loaded = {}

local function split(text, t)
  local result = {}

  local i = 1
  while i <= #text do
    local s, e = string.find(text, t, i)
    if s == nil then
      table.insert(result, text:sub(i))
      break
    else
      if s > i then
        table.insert(result, text:sub(i, s - 1))
      end

      i = e + 1
    end
  end

  return result
end

local function resolve(key)
  local tokens = split(key, "%.")
  local result = {}

  for i = 1, #tokens do
    local x = tokens[i]

    if x == "_" then
      table.remove(result, #result)
    else
      table.insert(result, x)
    end
  end

  return table.concat(result, ".")
end

return function(...)
  local base, fname = ...
  base = base or ""

  if fname ~= nil then
    local modbase = string.match(base, "([^.]*)$")
    local basename = string.match(fname, "([^/]*)%.lua$")

    if modbase == basename then
      base = base:sub(0, #base - #modbase - 1)
    end
  end

  return function(name)
    local key = resolve(base .. "." .. name)
    if loaded[key] ~= nil then
      return loaded[key]
    end

    local ok, mod = pcall(require, key)
    if not ok then
      loaded[key] = require(name)

      return loaded[key]
    else
      loaded[key] = mod

      return mod
    end
  end
end
