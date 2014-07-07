local m = {}
--require('enet')
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

local function serialize(t)
    local s = ""
    for i = 1, #t do
        local e = t[i]
        if type(e) == 'number' then
            s = s .. '%' .. tostring(e)
        elseif type(e) == 'string' then
            s = s .. '"' .. strEscape(e)  .. '"'
        elseif type(e) == 'table' and e['_ons'] then
            local id = e._ons.id
            s = s .. "#" .. tostring(id)
        end
        if i ~= #t then
            s = s .. " "
        end
    end
    return s
end

local function deserialize(s, world)
    local t = {}
    local mode = ''
    local i = 1
    local b = 1 -- first symbol
    local e = 1 -- last symbol
    while i <= #s do
        local c = s:sub(i, i)
        if mode == '' then
            if c == '"' then
                mode = 'string'
                b = i + 1
            elseif c == '%' then
                mode = 'number'
                b = i + 1
            elseif c == '#' then
                mode = 'object'
                b = i + 1
            end
        elseif mode == 'string' then
            if c == '\\' then
                i = i + 1
            elseif c == '"' then
                mode = ''
                e = i - 1
                t[#t+1] = strUnescape(s:sub(b, e))
            end
        elseif mode == 'number' then
            if c == ' ' then
                mode = ''
                e = i - 1
                t[#t+1] = tonumber(s:sub(b, e))
            end
        elseif mode == 'object' then
            if c == ' ' then
                mode = ''
                e = i - 1
                local id = tonumber(s:sub(b, e))
                for j = 1, #world do
                    if world[j]._ons.id == id then
                        t[#t+1] = world[j]
                        break
                    end
                end
            end
        end
        i = i + 1
    end
    return t
end

local function create(settings)
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
m.create = create
--test
do
    local serializetest = false
    if serializetest then
        local obj1 = {_ons = {id = 4}}
        local obj2 = {_ons = {id = 10}}
        local world = {obj1, obj2}
        local testTable = {'hello \\ """ \\" world', 5, obj1, 15, 13.04, obj2, 'blu""r"gh!'}
        local s = serialize(testTable)
        print(s)
        local u = deserialize(s, world)
        for i = 1, #testTable do
            print("Checking " .. tostring(u[i]) .. ' == ' .. tostring(testTable[i]))
            assert(testTable[i] == u[i])
        end
    end
end
--

return m
