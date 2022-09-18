
AddCSLuaFile()

function printf(...)
    print(string.format(...))
end

function MsgF(fmt, ...)
    MsgN(string.format(fmt, ...))
end
