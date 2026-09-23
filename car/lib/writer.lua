local CarWriter = {}
-- (major) * 2^8 + (minor)
CarWriter.version = 0 * 256 + 0

local function emitInt32(emit, n)
    emit (table.concat({
        string.char (n % 256),
        string.char (math.floor(n / 256) % 256),
        string.char (math.floor(n / 256 / 256) % 256),
        string.char (math.floor(n / 256 / 256 / 256) % 256)
    }, ""))
end

function CarWriter.create(emit)
    self = setmetatable({}, {
        __call = function (_, ...) return emit(...) end,
        __index = CarWriter
    })
    
    return self
end

function CarWriter.begin(emit)
    emit(("\x01[%s]CAR\x02"):format(CarWriter.version))
end

function CarWriter.write(emit, fname, body)
    emitInt32 (emit, #fname)
    emit (fname)
    emitInt32 (emit, #body)
    emit (body)
end

return CarWriter
