local argutils, Writer, Reader, tools = require "lib" (
    "argutils",
    "Writer",
    "Reader",
    "tools"
)

local cwd = shell.dir() .. "/"

local options =
    argutils.Options:new()
        :flag_of "help"
            :with_shortname "h"
            :with_description "show help message"
        :option_of "archive_file"
            :with_shortname "f"
            :with_description "set archive file name (ex: out.car)"
        :flag_of "do_extract"
            :with_shortname "x"
            :with_description "do extract .car archive"
        :flag_of "do_create"
            :with_shortname "c"
            :with_description "do create .car archive"
        :flag_of "do_list"
            :with_shortname "l"
            :with_description "do show .car archive content"
        :flag_of "verbose"
            :with_shortname "v"
            :with_description "set verbose mode"

local err, opts, positionals = argutils.parse(options, arg)

if err ~= nil or opts.archive_file == nil or opts.help then
    if err ~= nil then
        print(err .. "\n")
    end
    
    argutils.showHelp(options)
    
    return
end

local archive_file = shell.resolve(opts.archive_file)

for i = 1, #positionals do
    positionals[i] = shell.resolve(positionals[i])
end

if opts.do_extract then
    tools.extract (
        archive_file,
        { verbose = not not opts.verbose },
        positionals
    )
elseif opts.do_create then
    tools.create (
        archive_file,
        { verbose = not not opts.verbose },
        positionals
    )
elseif opts.do_list then
    tools.list (
        archive_file,
        { verbose = not not opts.verbose },
        positionals
    )
else
    print("Invalid archiver mode, you should set to one of extract, create, ... mode\n")
    
    argutils.showHelp(options)
end
