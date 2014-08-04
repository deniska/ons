-- Copyright (c) 2014 Denis Pobedrya <denis.pobedrya@gmail.com>
-- The code is licensed under MIT license, see LICENSE file for more info

local Ons = require('ons')
local world = {}
local ons
local font

local function createObj()
    local o = {x = 400, y = 300, text = "Test", red = true}
    o.move = function(self, x, y)
        self._lerp.x = x -- linearly interpolated values should be set
        self._lerp.y = y -- on server side using special _lerp table
    end
    o.chat = function(self, text)
        self.text = text
    end
    o.init = function(self, p, text, red)
        p.text = text
        p.red = red
    end
    o.setred = function(self, red)
        self.red = red
    end
    return o
end

local settings = {
    create = createObj,
    relay = {'chat', 'setred'},
    private = {'init'},
    client = {'move'},
    lerp = {'x', 'y'},
    unreliable = {'move'},
    tick = 0.05,
    debug = true
}

function love.load(params)
    local server
    local addr = "127.0.0.1:25780"
    if params[2] == 'server' then
        server = true
        addr = params[3] or addr
    elseif params[2] == 'client' then
        server = false
        addr = params[3] or addr
    else
        server = false
    end
    font = love.graphics.newFont(15)
    love.graphics.setFont(font)
    ons = Ons.create(settings)
    if server then
        ons:host(addr)
        ons:onCreate(function(obj)
            for i = 1, #world do
                obj:init(world[i], world[i].text)
            end
        end)
        love.window.setTitle("Server")
    else
        love.window.setTitle("Client")
        ons:connect(addr)
        ons:onTick(function ()
            local obj = ons:getClientObject()
            if obj then
                obj:move(love.mouse.getX(), love.mouse.getY())
            end
        end)
    end
    world = ons:getWorld()
end

function love.update(dt)
    ons:update(dt)
    world = ons:getWorld()
    local o = ons:getClientObject()
    if o then
        o.x = love.mouse.getX()
        o.y = love.mouse.getY()
    end
end

function love.draw()
    for i = 1, #world do
        local o = world[i]
        if o.red then
            love.graphics.setColor(255, 0, 0)
        else
            love.graphics.setColor(255, 255, 255)
        end
        love.graphics.print(o.text, o.x + 30, o.y + 30)
        love.graphics.circle('fill', o.x, o.y, 20)
    end
end

function love.textinput(text)
    local o = ons:getClientObject()
    if o then
        o:chat(o.text .. text)
    end
end

function love.mousepressed(x, y, button)
    local o = ons:getClientObject()
    if o then
        o:setred(true)
    end
end

function love.mousereleased(x, y, button)
    local o = ons:getClientObject()
    if o then
        o:setred(false)
    end
end

function love.keypressed(key, isrepeat)
    local o = ons:getClientObject()
    if o and key == 'backspace' then
        o:chat(o.text:sub(0, -2))
    end
end

function love.quit()
    ons:disconnect()
end
