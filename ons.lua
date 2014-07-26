local m = {}
require('enet')

local function findObjectById(world, id)
    for j = 1, #world do
        if world[j]._ons.id == id then
            return world[j]
        end
    end
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
        elseif type(e) == 'boolean' then
            if e then
                s = s .. 't'
            else
                s = s .. 'f'
            end
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
    s = s .. " "
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
            elseif c == 't' then
                t[#t+1] = true
            elseif c == 'f' then
                t[#t+1] = false
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
                t[#t+1] = findObjectById(world, id)
            end
        end
        i = i + 1
    end
    return t
end


--settings: create, client, server, relay, lerp, tick

local function log(ons, m)
    if ons.debug then
        print(m)
    end
end

--called when patched object function call occures
local function onCall(call, params, type, ons)
    local msg = {call}
    local obj = params[1]
    for i = 1, #params do
        msg[#msg + 1] = params[i]
    end
    if ons.type == 'client' then
        --may call client or relay methods, only yourself
        if (obj._ons.client[call] or obj._ons.relay[call]) and obj == ons.clientObject then
            ons.conn:send(serialize(msg), 1)
        end 
    elseif ons.type == 'server' then
        --may call server or relay or private
        if obj._ons.server[call] or obj._ons.relay[call] then
            ons.enethost:broadcast(serialize(msg), 1)
        elseif obj._ons.private[call] then
            obj._ons.peer:send(serialize(msg), 1)
        end
    end
end

local function wrap(obj, list, type, ons)
    obj._ons[type] = {}
    obj._ons.real = obj._ons.real or {}
    if list == nil then return end
    for i = 1, #list do
        local f = list[i]
        obj._ons[type][f] = obj[f]
        obj._ons.real[f] = obj[f]
        obj[f] = function(...)
            onCall(f, {...}, type, ons)
            obj._ons[type][f](...)
        end
    end
end

local function createObject(ons, id)
    local settings = ons.settings
    local obj = settings.create()
    ons.curId = ons.curId + 1
    id = id or ons.curId
    log(ons, 'Creating object with id ' .. id)
    obj._ons = {}
    obj._ons.id = id
    wrap(obj, settings.client, 'client', ons)
    wrap(obj, settings.server, 'server', ons)
    wrap(obj, settings.relay, 'relay', ons)
    wrap(obj, settings.private, 'private', ons)
    obj._ons.frames = {}
    for i = 1, 3 do
        obj._ons.frames[i] = {}
        for j = 1, #ons.settings.lerp do
            obj._ons.frames[i][ons.settings.lerp[j]] = obj[ons.settings.lerp[j]]
        end
    end
    obj._lerp = obj._ons.frames[3]
    obj._ons.ticktimer = ons.tick
    ons.world[#ons.world + 1] = obj
    return obj
end

local function deleteObject(ons, id)
    log(ons, "Deleting object with id " .. id)
    local newWorld = {}
    for i = 1, #ons.world do
        if ons.world[i]._ons.id ~= id then
            newWorld[#newWorld + 1] = ons.world[i] 
        end
    end
    ons.world = newWorld
end

local function lerpShift(obj, ons)
    local lerps = ons.settings.lerp
    for i = 1, #lerps do
        for j = 2, 3 do
            obj._ons.frames[j - 1][lerps[i]] = obj._ons.frames[j][lerps[i]]
        end
    end
    obj._ons.ticktimer = obj._ons.ticktimer + ons.tick
end

--protocol
--{"!C", id1, id2...} server -> client on new client connect
--{"!D", id1, id2...} server -> client on client disconnect
--{"!I", id} server -> client send clientObject id
--{method, param1, param2...} server <-> client on method call, param1 is obj

local function onEvent(event, ons)
    if event.type == 'connect' then
        if ons.type == 'server' then
            event.peer:ping_interval(50)
            log(ons, 'Client connected to server')
            --create object
            local t = createObject(ons)
            t._ons.peer = event.peer
            --send world info to client
            local msg = {"!C"}
            for i = 1, #ons.world do
                msg[#msg + 1] = ons.world[i]._ons.id
            end
            event.peer:send(serialize(msg), 1)
            event.peer:send(serialize({"!I", t._ons.id}), 1)
            --send info about client to the world
            local m = serialize({"!C", t._ons.id})
            for i = 1, #ons.world do
                if ons.world[i] ~= t then
                    ons.world[i]._ons.peer:send(m, 1)
                end
            end
            if ons.onCreateHandler then
                ons.onCreateHandler(t)
            end
            log(ons, 'Number of clients: ' .. tostring(#ons.world))
        end
    elseif event.type == 'receive' then
        local t = deserialize(event.data, ons.world)
        if #t < 2 then return end
        if ons.type == 'client' then
            if t[1] == "!C" then
                --create objects
                for i = 2, #t do
                    local o = createObject(ons, t[i])
                    if ons.onCreateHandler then
                        ons.onCreateHandler(o)
                    end
                end
            elseif t[1] == "!D" then
                --delete objects
                for i = 2, #t do
                    local o = findObjectById(ons.world, t[i])
                    if ons.onDeleteHandler then
                        ons.onDeleteHandler(o)
                    end
                    deleteObject(ons, t[i])
                end
            elseif t[1] == "!L" then
                local lerps = ons.settings.lerp
                local k = 1
                local curObj = nil
                for j = 2, #t do
                    if type(t[j]) == 'table' and t[j]._ons then
                        k = 1
                        curObj = t[j]
                        --lerpShift(curObj, ons)
                    elseif type(t[j]) == 'number' then
                        if curObj then
                            local l = lerps[k]
                            if l then
                                curObj._lerp[l] = t[j]
                            end
                            k = k + 1
                        end
                    end
                    --log(ons, "Lerp recv: " .. t[3] .. " " .. t[4])
                end
            elseif type(t[2]) == 'table' and t[2]._ons then
                --call real method
                local params = {}
                for i = 2, #t do
                    params[#params + 1] = t[i]
                end
                t[2]._ons.real[t[1]](unpack(params))
            elseif t[1] == "!I" then
                log(ons, 'Id is ' .. t[2])
                local id = t[2]
                local o = findObjectById(ons.world, id)
                ons.clientObject = o
            end
        elseif ons.type == 'server' then
            --if relay or client, call real method
            if type(t[2]) == 'table' and t[2]._ons then
                local o = t[2]
                if o._ons.peer ~= event.peer then return end --can't call others methods
                local m = t[1]
                local params = {}
                if o._ons.relay[m] or o._ons.client[m] then
                    for i = 2, #t do
                        params[#params + 1] = t[i]
                    end
                    o._ons.real[m](unpack(params))
                end
                --relay relayed methods
                if o._ons.relay[m] then
                    for i = 1, #ons.world do
                        if ons.world[i] ~= o then
                            ons.world[i]._ons.peer:send(event.data, 1)
                        end
                    end
                end
            end
        end
    elseif event.type == 'disconnect' then
        if ons.type == 'server' then
            log(ons, 'Client disconnected from server')
            local o = nil
            for i = 1, #ons.world do
                if ons.world[i]._ons.peer == event.peer then
                    o = ons.world[i]
                    break
                end
            end
            if o then
                ons.enethost:broadcast(serialize({"!D", o._ons.id}), 1)
                if ons.onDeleteHandler then
                    ons.onDeleteHandler(o)
                end
                deleteObject(ons, o._ons.id)
            end
            log(ons, 'Number of clients: ' .. tostring(#ons.world))
        end
    end
end

local function lerp(a, b, c)
    return a + (b - a) * c
end

local function isUpdated(obj, ons)
    local lerps = ons.settings.lerp
    for i = 1, #ons.settings.lerp do
        local v1 = obj._ons.frames[2][lerps[i]]
        local v2 = obj._ons.frames[3][lerps[i]]
        if v1 ~= v2 then return true end
    end
    return false
end

local function lerpSend(ons)
    if ons.type ~= 'server' then return end
    local lerps = ons.settings.lerp
    for i = 1, #ons.world do
        local peer = ons.world[i]._ons.peer
        local msg = {"!L"}
        for j = 1, #ons.world do
            local obj = ons.world[j]
            if i ~= j and isUpdated(obj, ons) then
                msg[#msg + 1] = obj
                for k = 1, #lerps do
                    msg[#msg + 1] = obj._ons.frames[3][lerps[k]]
                end
            end
            peer:send(serialize(msg), 0)
        end
    end
    for i = 1, #ons.world do
        lerpShift(ons.world[i], ons)
    end
end

local function lerpUpdate(ons, dt)
    local lerps = ons.settings.lerp
    --local t = (ons.tick - ons.ticktimer) / ons.tick
    for i = 1, #ons.world do
        local obj = ons.world[i]
        obj._ons.ticktimer = obj._ons.ticktimer - dt
    end
    for i = 1, #ons.world do
        local obj = ons.world[i]
        if obj ~= ons:getClientObject() then
            for j = 1, #lerps do
                local t = (ons.tick - obj._ons.ticktimer) / ons.tick
                local v1 = obj._ons.frames[1][lerps[j]]
                local v2 = obj._ons.frames[2][lerps[j]]
                obj[lerps[j]] = lerp(v1, v2, t)
                if obj._ons.ticktimer < 0 then
                    --obj._ons.ticktimer = obj._ons.ticktimer + ons.tick
                    lerpShift(obj, ons)
                end
            end
        end
    end
end

local function create(settings)
    local ons = {}
    if settings.debug then
        ons.debug = true
    else
        ons.debug = false
    end
    ons.settings = settings
    ons.curId = 0
    ons.world = {}
    ons.enethost = nil
    ons.clientObject = nil
    ons.type = 'offline'
    ons.tick = settings.tick or 50
    ons.ticktimer = ons.tick
    ons.getClientObject = function(self)
        return self.clientObject
    end
    ons.getWorld = function(self)
        return self.world
    end
    ons.host = function(self, addr)
        self.enethost = enet.host_create(addr, 64, 2)
        ons.type = 'server'
    end
    ons.connect = function(self, addr)
        self.enethost = enet.host_create()
        self.conn = self.enethost:connect(addr, 2)
        self.type = 'client'
    end
    ons.getType = function(self)
        return self.type
    end
    ons.update = function(self, dt)
        local ev = self.enethost:service()
        if ev ~= nil then
            onEvent(ev, self)
            while true do
                local event = self.enethost:check_events()
                if event ~= nil then
                    onEvent(event, self)
                else
                    break
                end
            end
        end
        self.ticktimer = self.ticktimer - dt
        if self.ticktimer <= 0 then
            if self.onTickHandler then
                self.onTickHandler()
            end
            lerpSend(self)
            self.ticktimer = self.ticktimer + self.settings.tick
        end
        lerpUpdate(self, dt)
    end
    ons.onCreate = function(self, f)
        self.onCreateHandler = f
    end
    ons.onDelete = function(self, f)
        self.onDeleteHandler = f
    end
    ons.onTick = function(self, f)
        self.onTickHandler = f
    end
    ons.disconnect = function(self, obj)
        if self:getType() == 'server' and obj then
            obj.peer:disconnect()
        elseif self:getType() == 'client' then
            self.conn:disconnect()
            self.enethost:flush()
        end
    end
    return ons
end
m.create = create

return m
