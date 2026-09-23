local Writer = require "@/writer.lua"
local Reader = require "@/reader.lua"

local tools = {}

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

function tools.create(target, options, inputs)
    local f = io.open(target, "w+")

    local w = Writer.create (function (x) return f:write(x) end)
    
    w:begin()

    local cwd = shell.resolve(".")

    for kind, name in getAllFilePath(inputs) do
        if kind == FileEntryKind.File and name ~= target then
            local g = io.open(name, "r")
            
            name = name:sub(#cwd+2)
            w:write(name, g:read("a"))
            
            g:close()
            
            if options.verbose then
                io.write(name .. "\n")
            end
        end
    end
    
    f:close()
end

function tools.extract(target, options, inputs)
    if fs.isDir(target) or not fs.exists(target) then
        io.write("Target file is not file or not exists.\n")
        
        return
    end
    
    local f = fs.open(target, "r")
    local r = Reader.create (function (n)
        return f.read(n)
    end)
    
    repeat
        local ok, version = r:begin()
        if not ok then
            if options.verbose then
                io.write(("Invalid file header: %s\n"):format(version))
            end
            
            break
        end
        
        if options.verbose then
            io.write(
                ("Archive Version: %s.%s\n\n")
                :format(
                    math.floor(version / 256),
                    version % 256
                )
            )
        end

        local filters = {}
        for i = 1, #inputs do
            filters[inputs[i]] = true
        end

        local cwd = shell.resolve(".")
        
        while true do
            local ok, fname, body = r:next()
            if not ok then
                break
            end

            fname = shell.resolve(fs.combine("./" .. fname))

            if #inputs == 0 or filters[fname] then
                io.write(("Extract %s ... %s bytes\n"):format(fname:sub(#cwd + 2), #body))

                local parent = fs.getDir(fname)
                if not fs.isDir(parent) then
                    fs.makeDir(parent)
                end

                local f = io.open(fname, "w+")
                f:write(body)
                f:close()
            else
                if options.verbose then
                    io.write(("Ignore %s ... %s bytes\n"):format(fname:sub(#cwd + 2), #body))
                end
            end
        end
    until 1
        
    f.close()
end

function tools.list(target, options, inputs)
    if fs.isDir(target) or not fs.exists(target) then
        io.write("Target file is not file or not exists.\n")
        
        return
    end
    
    local f = fs.open(target, "r")
    local r = Reader.create (function (n)
        return f.read(n)
    end)
    
    repeat
        local ok, version = r:begin()
        if not ok then
            if options.verbose then
                io.write(("Invalid file header: %s\n"):format(version))
            end
            
            break
        end
        
        if options.verbose then
            io.write(
                ("Archive Version: %s.%s\n\n")
                :format(
                    math.floor(version / 256),
                    version % 256
                )
            )
        end
        
        while true do
            local ok, fname, body = r:next()
            if not ok then
                break
            end
            
            io.write(("%s ... %s bytes\n"):format(fname, #body))
        end
    until 1
        
    f.close()
end

return tools
