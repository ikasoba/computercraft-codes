local argutils = {}

function argutils.parse(options, args)
    local optnames = options.definitions
    local opts = {}
    local positionals = {}
    
    local shorts = {}
    for name, opt in pairs(optnames) do
        if opt.short ~= nil then
            shorts[opt.short] = name
        end
    end

    local i = 1
    while i <= #args do
        local x = args[i]
        local optionName = nil
        
        local option = nil
        if string.match(x, "^-[^-]*$") then
            local name = string.sub(x, 2)
            
            if shorts[name] == nil then
                return ("Invalid short option name (at %s): %s"):format(i, name), nil, nil
            end
            
            optionName = shorts[name]
            option = optnames[optionName]
        elseif string.match(x, "^-%-[^-]*$") then
            local name = string.sub(x, 3)
            
            if optnames[name] == nil then
                return ("Invalid option name (at %s): %s"):format(i, name), nil, nil
            end
            
            optionName = name
            option = optnames[name]
        else
            option = true
            optionName = x
        end
        
        if option == true then
            table.insert(positionals, x)
        else
            local value = nil
            
            if option.is_flag then
                value = true
            else
                if i + 1 > #args then
                    return ("Invalid argument (at %s): required option value after %s"):format(i, x), nil, nil
                end
                
                i = i + 1
                
                value = args[i]
            end
            
            if not option.is_multiple then
                opts[optionName] = value
            else
                if opts[optionName] ~= nil then
                    opts[optionName] = {}
                end
                
                table.insert(opts[optionName], value)
            end
        end
        
        
        i = i + 1
    end
    
    return nil, opts, positionals
end

function argutils.showHelp(options, emit)
    emit = emit or io.write

    for _, name in ipairs(options.names) do
        local opt = options.definitions[name]
    
        if opt.short ~= nil then
            emit(("--%s, -%s"):format(name, opt.short))
        else
            emit(("--%s"):format(name))
        end
        
        if not opt.is_flag then
            if not opt.is_multiple then
                emit((" <%s>"):format(name))
            else
                emit((" <%s...>"):format(name))
            end
        end
             
        emit("\n  " .. (opt.description or "(no description)") .. "\n")
   end
end

local Options = {}
Options.__index = Options
argutils.Options = Options

function Options:new()
    self = setmetatable({}, Options)
    
    self.definitions = {}
    self.names = {}
    self.last_name = nil
    
    return self
end

function Options:option_of(name, opt)
    self.definitions[name] = opt or {}
    table.insert(self.names, name)
    
    self.last_name = name
    
    return self
end

function Options:flag_of(name)
    return self:option_of(name, { is_flag = true })
end

function Options:with_shortname(short)
    if self.last_name ~= nil then
        self.definitions[self.last_name].short = short
    end
    
    return self
end

function Options:with_description(description)
    if self.last_name ~= nil then
        self.definitions[self.last_name].description = description
    end
    
    return self
end

return argutils
