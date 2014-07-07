local m = {}
require('enet')
--settings: create, client, server, relay, lerp, tick

--called when enet event occures
local function onEvent(event, ons)

end

--called when patched object function call occures
local function onCall(call, params, type, ons)

end

local function wrap(obj, list, type, ons)
    obj._ons[type] = {}
    for i = 1, #list do
        local f = list[i]
        obj._ons[type][f] = obj[f]
        obj[f] = function(...)
            onCall(f, {...}, type, ons)
            obj._ons[type][f](...)
        end
    end
end

local function createObject(settings, ons)
    local obj = settings.create()
    ons.curId = ons.curId + 1
    obj._ons = {}
    obj._ons.id = ons.curId
    wrap(obj, settings.client, 'client', ons)
    wrap(obj, settings.server, 'server', ons)
    wrap(obj, settings.relay, 'relay', ons)
    ons.world[#ons.world + 1] = obj
    return obj
end

local function strEscape(s)
    local e = ''
    for i = 1, #s do
        local c = s:sub(i, i) 
        if c == '\\' then
            e = e .. '\\\\'
        elseif c == '"' then
            e = e .. '\\"'
        else
            e = e .. c
        end
    end
    return e
end

local function strUnescape(e)
    local s = ''
    local i = 1
    while i <= #e do
        local c = e:sub(i, i)
        if c == '\\' then
            i = i + 1
            c = e:sub(i, i)
        end
        s = s .. c
        i = i + 1
    end
    return s
end

local function serialize(t, world)
    local s = ""
    for i = 1, #t
        local e = t[i]
        if type(e) == 'number' then
            s = s .. tostring(number)
        elseif type(e) == 'string' then
            local escaped = e:gsub("\\")
            local a = '"' .. escaped .. '"'
        end
    end
    return s
end

local function unserialize(s, world)
    local t = {}
    return t
end

local function m.create(settings)
    local ons = {}
    ons.curId = 0
    ons.world = {}
    ons.enethost = nil
    ons.clientObject = nil
    ons.type = 'offline'
    ons.host = function(self, addr)
        self.enethost = enet.create_host(settings.addr, 64, 2)
        ons.type = 'server'
    end
    ons.connect = function(self, addr)
        self.enethost = enet.create_host(nil, 1, 2)
        self.conn = self.enethost:connect(addr)
        self.type = 'client'
    end
    ons.getType = function(self)
        return self.type
    end
    ons.update = function(self, dt)
        local event = host:service()
    end
end

return m
