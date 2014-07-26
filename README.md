#ONS

##About the project
ONS (objective networking system) is a [lua-enet](http://leafo.net/lua-enet/) wrapper allowing for
easy creation of multiplayer games. It is intended to use with [LÖVE](http://love2d.org/)
though the only dependency is enet.

##Usage

First you need to provide object constructor:

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

Then you need to set up a settings table.

    local settings = {
        create = createObj,
        relay = {'chat', 'setred'},
        private = {'init'},
        client = {'move'},
        lerp = {'x', 'y'},
        tick = 0.05,
        debug = true
    }

`relay` methods are methods which may be called on a client and calls will be
broadcasted to every client  
`private` methods are methods which *may not* be called on a client and calls will
be sent only to a specific client  
`client` methods are methods which may be called on a client and calls will not be
broadcasted  
`server` methods are methods which *may not* be called on a client and calls will
be  
`lerp` are numeric values which will be linearly interpolated on server and client sides, change
values in `_lerp` table on server side to change those values  
`tick` is a period of time between frame updates from a server  
`debug = true` will print out some useful info in a terminal

To create a system, use ons.create method:

    local ons = require("ons")
    local system = ons.create(settings)

Methods of a `system`:

    system:host(addr) -- Create a server
    system:connect(addr) -- Connect to a server
    system:disconnect(obj) -- On a client disconnects yourself, on a server disconnects a specific client
    system:getClientObject() -- If connected returns a client object you may call methods of on a client
    system:getWorld() -- Returns a world, table of all objects in a world
    system:update(dt) -- Updates linear intorpolations and does networking stuff, need to be called periodically
    system:getType() -- Possible return values are 'offline', 'client' and 'server'
    system:onCreate(function(obj)) -- Callback to be called after new client connects
    system:onDelete(function(obj)) -- Callback to be called after a client disconnects
    system:onTick(function()) -- Callback to be called every settings.tick values of time

##Example

See `main.lua` file for a complete client/server example. It can be run as
`love . server [addr]` and `love . client [addr]`

##Warning

This project is highly immature and untested, use on your own risk. Linear interpolation
code is not ready yet for fast paced games because it doesn't take into consideration various latency effects.
