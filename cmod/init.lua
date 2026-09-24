local loaded = {}

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
    local key = base .. "." .. name
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
