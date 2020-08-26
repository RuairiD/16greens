-- START CLASSIC
local Object = {}
Object.__index = Object


function Object:new()
end


function Object:extend()
    local cls = {}
    for k, v in pairs(self) do
        if sub(k, 1, 2) == "__" then
            cls[k] = v
        end
    end
    cls.__index = cls
    cls.super = self
    setmetatable(cls, self)
    return cls
end


function Object:implement(...)
    for _, cls in pairs({...}) do
        for k, v in pairs(cls) do
            if self[k] == nil and type(v) == "function" then
                self[k] = v
            end
        end
    end
end


function Object:is(T)
    local mt = getmetatable(self)
    while mt do
        if mt == T then
            return true
        end
        mt = getmetatable(mt)
    end
    return false
end


function Object:__tostring()
    return "Object"
end


function Object:__call(...)
    local obj = setmetatable({}, self)
    obj:new(...)
    return obj
end
-- END CLASSIC

-- START STATE MANAGEMENT
local STATES = {
    GAME = "GAME",
    TITLE = "TITLE",
}
local currentState

-- END STATE MANAGEMENT

-- START GAME

local WALL_TILES = {
    3, 4, 5,
    19, 21,
    35, 36, 37,
}

local function isWallTile(tile)
    for _, wallTile in ipairs(WALL_TILES) do
        if tile == wallTile then
            return true
        end
    end
    return false
end

local function checkMove(x, y, newX, newY, width, height)
    -- Simulates a movement from (x, y) to (newX, newY).
    -- x and y movements are calculated separately to provide
    -- accurate collision information. No bouncing is applied;
    -- if a wall is struck, the movement simply stops for that
    -- axis.
    local resultX, resultY
    local collidedX = false
    local collidedY = false

    local xStep = 0
    local yStep = 0
    if newX ~= x then
        xStep = 0.01 * (newX - x)/abs(newX - x)
    end
    if newY ~= y then
        yStep = 0.01 * (newY - y)/abs(newY - y)
    end

    local tile
    if xStep ~= 0 then
        for xi = x, newX, xStep do
            -- If the ball is travelling to the right,
            -- include the width in the calculation so
            -- the correct edge is checked for collision.
            local xToCheck = xi
            if xStep > 0 then
                xToCheck = xi + (width - 1)
            end
            tile = mget(
                flr(xToCheck/8),
                flr(y/8)
            )
            if isWallTile(tile) then
                resultX = xi - xStep
                collidedX = true
                break
            end
        end
    end
    if not resultX then
        resultX = newX
    end

    if yStep ~= 0 then
        for yi = y, newY, yStep do
            -- If the ball is travelling down,
            -- include the height in the calculation so
            -- the correct edge is checked for collision.
            local yToCheck = yi
            if yStep > 0 then
                yToCheck = yi + (height - 1)
            end
            tile = mget(
                flr(resultX/8),
                flr(yToCheck/8)
            )
            if isWallTile(tile) then
                resultY = yi - yStep
                collidedY = true
                break
            end
        end
    end
    if not resultY then
        resultY = newY
    end

    return resultX, resultY, collidedX, collidedY
end

local Ball = Object:extend()

Ball.MAX_SPEED = 4
Ball.FRICTION = 0.99
Ball.SIZE = 4

function Ball:new(x, y)
    self.x = x
    self.y = y
    self.velX = 0
    self.velY = 0
    self.isStopped = true
end

function Ball:hit(angle, power)
    if not self.isStopped then
        return
    end
    self.velX = power * Ball.MAX_SPEED * cos(angle)
    self.velY = power * Ball.MAX_SPEED * sin(angle)
    self.isStopped = false
end

function Ball:update()
    if not self.isStopped then
        local newX, newY = self.x, self.y

        newX = self.x + self.velX
        newX, _, collidedX, _ = checkMove(self.x, self.y, newX, newY, Ball.SIZE, Ball.SIZE)
        if collidedX then
            self.velX = self.velX * -1
        end

        newY = self.y + self.velY
        _, newY, _, collidedY = checkMove(newX, self.y, newX, newY, Ball.SIZE, Ball.SIZE)
        if collidedY then
            self.velY = self.velY * -1
        end

        self.x = newX
        self.y = newY

        self.velX = self.velX * Ball.FRICTION
        self.velY = self.velY * Ball.FRICTION
        if sqrt(self.velX * self.velX + self.velY * self.velY) < 0.1 then
            self.velX = 0
            self.velY = 0
            self.isStopped = true
        end
    end
end

function Ball:draw()
    palt(0, false)
    palt(14, true)

    spr(17, self.x - (8 - Ball.SIZE)/2, self.y - (8 - Ball.SIZE)/2)
end

local ball
local currentHole

function initGame()
    ball = Ball(32, 32) 
end


function updateGame()
    if btnp(5) then
        ball:hit(rnd(), 1)
    end
    ball:update()
end


function drawGame()
    map(0, 0, 0, 0, 16, 16)
    ball:draw()
end


-- END GAME

-- START MAIN

function _init()
    currentState = STATES.GAME
    initGame()
end

function _update60()
    if currentState == STATES.GAME then
        updateGame()
    end
end

function _draw()
    cls()
    if currentState == STATES.GAME then
        drawGame()
    end
end
-- END MAIN
