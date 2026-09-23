local CarReader = {}

local function loadInt32(t)
    if t == nil then
        return nil
    end

    local n = 0
    local m = 1
    
    for i = 1, 4 do
        n = n + string.byte(t, i) * m
        m = m * 256
    end
    
    return n
end

function CarReader.create(read)
    self = setmetatable({}, {
        __call = function (_, ...) return read(...) end,
        __index = CarReader
    })
    
    return self
end

function CarReader.begin(read)
    if read (1) ~= "\x01" then
        return false, nil
    end
    
    if read (1) ~= "[" then
        return false, nil
    end
    
    local version = 0
    
    local n = 1
    while true do
        local chr = read (1)
        if chr == "]" then
            break
        elseif chr == nil then
            return false, nil
        end
        
        chr = string.byte(chr)
        
        if chr < 48 or chr > 57 then
            return false, nil
        end
        
        version = version + (chr - 48) * n
        
        n = n * 10
    end
    
    
    if read (4) ~= "CAR\x02" then
        return false, nil
    end
    
    return true, version
end

function CarReader.next(read)
    local fname_size = loadInt32(read(4))
    if fname_size == nil then
        return false, nil, nil
    end
    
    local fname = read (fname_size)
    if fname == nil then
        return false, nil, nil
    end
    
    local body_size = loadInt32(read(4))
    if body_size == nil then
        return false, nil, nil
    end
    
    local body = read (body_size)
    if body == nil then
        return false, nil, nil
    end
    
    return true, fname, body
end

return CarReader
