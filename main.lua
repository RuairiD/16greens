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
local function drawBox(x, y, width, height)
    -- Shadow
    rectfill(
        x, y,
        x + width, y + height + 1,
        5
    )
    -- White outline
    rectfill(
        x, y,
        x + width, y + height,
        7
    )
    -- Black box
    rectfill(
        x + 1, y + 1,
        x + 1 + width - 2, y + 1 + height - 2,
        0
    )
end

-- START PHYSICS
local WALL_TILES = {
    3, 4, 5,
    19, 21,
    35, 36, 37,
    6, 7, 8,
    22,
}


local WATER_TILES = {
    48, 49, 50,
    64, 65, 66,
    80, 81, 82,
}


local WATER_FRAMES = {
    [48] = { 128, 131 },
    [49] = { 129, 132 },
    [50] = { 130, 133 },
    [64] = { 144, 147 },
    [65] = { 145, 148 },
    [66] = { 146, 149 },
    [80] = { 160, 163 },
    [81] = { 161, 164 },
    [82] = { 162, 165 },
}


local RAMPS = {
    WEST = 51,
    NORTH = 52,
    EAST = 67,
    SOUTH = 68,
}


local function isInTileset(tile, tileset)
    for _, candidateTile in ipairs(tileset) do
        if tile == candidateTile then
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
            if isInTileset(tile, WALL_TILES) then
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
            if isInTileset(tile, WALL_TILES) then
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


local function collides(x1, y1, w1, h1, x2, y2, w2, h2)
    return (
        x1 <= x2 + w2 and
        x1 + w1 >= x2 and
        y1 <= y2 + h2 and
        y1 + h1 >= y2
    )
end


local function containsPoint(px, py, x, y, w, h)
    return (
        px >= x and px <= x + w and
        py >= y and py <= y + h
    )
end
-- END PHYSICS

local SFX = {
    SPLASH = 63,
    BOUNCE = 62,
    STROKE = 61,
    SINK = 60,
    SKIM = 58,
    SELECT = 59,
}

local pin
local sparks
local SPARK_LIFE_MAX = 60
local SPARK_COLORS = { 1, 2, 3, 8, 9, 10, 11, 12, }

local function resetSparks(x, y)
    for i, spark in ipairs(sparks) do
        spark.x = x
        spark.y = y
        local angle = i/#sparks
        spark.velX = cos(angle) * 0.75
        spark.velY = sin(angle) * 0.75
        spark.t = SPARK_LIFE_MAX
    end
end

local splashParticles
local SPLASH_PARTICLE_LIFE_MAX = 25
local SPLASH_PARTICLE_LIFE_MAX_VARIANCE = 10
local SPLASH_COLORS = { 1, 12, }

local function resetSplashParticles(x, y)
    for i, splashParticle in ipairs(splashParticles) do
        splashParticle.x = x
        splashParticle.y = y
        local angle = i/#splashParticles
        splashParticle.velX = cos(angle) * 0.25
        splashParticle.velY = sin(angle) * 0.25
        splashParticle.tMax = SPLASH_PARTICLE_LIFE_MAX + rnd(SPLASH_PARTICLE_LIFE_MAX_VARIANCE)
        splashParticle.t = splashParticle.tMax
    end
end

local Ball = Object:extend()

Ball.MAX_SPEED = 8
Ball.FRICTION = 0.98
Ball.SIZE = 4
Ball.RAMP_SPEED_CHANGE_RATE = 0.05
Ball.SPRITES = {
    [1] = 17,
    [2] = 53,
    [3] = 54,
    [4] = 55,
}

function Ball:new(x, y)
    self.x = x
    self.y = y
    self.velX = 0
    self.velY = 0
    self.isStopped = true
    self.isSunk = false
end

function Ball:reset(x, y)
    self.isSunk = false
    self.isStopped = true
    self.velX = 0
    self.velY = 0
    self.x = x
    self.y = y
end

function Ball:hit(angle, power)
    if not self.isStopped then
        return
    end
    self.velX = power * Ball.MAX_SPEED * cos(angle)
    self.velY = power * Ball.MAX_SPEED * sin(angle)
    self.isStopped = false
    sfx(SFX.STROKE)
end

function Ball:applyRamp(direction)
    if direction == 'NORTH' then
        self.velY = self.velY - Ball.RAMP_SPEED_CHANGE_RATE
    elseif direction == 'SOUTH' then
        self.velY = self.velY + Ball.RAMP_SPEED_CHANGE_RATE
    elseif direction == 'WEST' then
        self.velX = self.velX - Ball.RAMP_SPEED_CHANGE_RATE
    elseif direction == 'EAST' then
        self.velX = self.velX + Ball.RAMP_SPEED_CHANGE_RATE
    end
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

        -- Check for ramps
        local onRamp = false
        local currentTile = mget(
            flr((self.x + Ball.SIZE/2)/8),
            flr((self.y + Ball.SIZE/2)/8)
        )
        for direction, tile in pairs(RAMPS) do
            if tile == currentTile then
                onRamp = true
                self:applyRamp(direction)
                break
            end
        end

        self.velX = self.velX * Ball.FRICTION
        self.velY = self.velY * Ball.FRICTION
        local speed = sqrt(self.velX * self.velX + self.velY * self.velY)
        -- Ball cannot stop on a ramp.
        if not onRamp and speed < 0.1 then
            self.velX = 0
            self.velY = 0
            self.isStopped = true
        end

        if collidedX or collidedY then
            sfx(SFX.BOUNCE)
        end

        if containsPoint(
            self.x + Ball.SIZE/2, self.y + Ball.SIZE/2,
            pin.x + 2, pin.y + 2, 4, 4
        ) then
            if not self.isSkimming then
                if speed < 3 then
                    self.isSunk = true
                    self.isStopped = true
                    sfx(SFX.SINK)
                    resetSparks(pin.x + 4, pin.y + 4)
                else
                    sfx(SFX.SKIM)
                    self.velX = self.velX * 1/2
                    self.velY = self.velY * 1/2
                    -- Set isSkimming flag to prevent ball skimming every frame
                    -- ball is over hole (and losing too much speed as a result)
                    self.isSkimming = true
                end
            end
        else
            self.isSkimming = false
        end
    end
end

function Ball:draw(playerNumber)
    spr(Ball.SPRITES[playerNumber], self.x - (8 - Ball.SIZE)/2, self.y - (8 - Ball.SIZE)/2)
end

-- Distance from ball where the line should start.
local ANGLE_INDICATOR_BUFFER = 4
local ANGLE_INDICATOR_LENGTH = 24
local ANGLE_CHANGE_RATE = 0.0025

local POWER_BAR_WIDTH = 44
local POWER_BAR_HEIGHT = 8
local POWER_BAR_MARGIN = 1
local POWER_BAR_X = 128 - POWER_BAR_WIDTH - POWER_BAR_MARGIN - 3
local POWER_BAR_Y = POWER_BAR_MARGIN
local POWER_CHANGE_RATE = 0.02

local NEXT_HOLE_TIMER_MAX = 120
local WATER_TIMER_MAX = 60

local balls
local ballOrigin
local currentHole
local playerCount
local activePlayer
local scores
local angle
-- Flag used to denote when player has started taking
-- stroke. Used to prevent accidentally playing stroke when
-- pressing X to dismiss score alert or something.
local charging
local power
local powerIncreasing
local strokePlayed
local playerHasCompletedHole
local holeCompleted
local nextHoleTimer
local waterTimer
-- Timer preventing user input straight after scene change.
local gameStartTimer
local showingScore
local roundOver
local showingScorecard

local waterTiles
local waterAnimationFrame = 0


local function getHolePosition(holeNumber)
    -- Overflow from final hole to first hole.
    if holeNumber > 16 then
        holeNumber = 1
    end
    local holeY = 0
    local holeX = holeNumber - 1
    if holeNumber > 8 then
        holeY = 1
        holeX = (16 - holeNumber)
    end
    return holeX, holeY
end


function initHole(holeNumber)
    activePlayer = 1
    playerHasCompletedHole = {}
    holeCompleted = false
    showingScore = false
    roundOver = false
    nextHoleTimer = 0
    waterTimer = 0

    local holeX, holeY = getHolePosition(holeNumber)

    for x = holeX * 16, holeX * 16 + 16 do 
        for y = holeY * 16, holeY * 16 + 16 do
            local tile = mget(x, y)
            if tile == 18 then
                pin = {
                    x = x * 8,
                    y = y * 8,
                }
            elseif tile == 16 then
                ballOrigin = {
                    x = x * 8,
                    y = y * 8,
                }
                for _, ball in ipairs(balls) do
                    ball:reset(x * 8 + 2, y * 8 + 2)
                end
            end
        end
    end

    angle = flr(atan2(pin.x - balls[1].x, pin.y - balls[1].y) * 8) * 0.125
end


function initGame(players)
    playerCount = players
    gameStartTimer = 60
    power = 0
    powerIncreasing = true
    angle = 0.25
    balls = {}
    for i=1,playerCount do
        add(balls, Ball(0, 0))
    end
    scores = {}
    for p=1, playerCount do
        scores[p] = {}
        for h=1,16 do
            scores[p][h] = 0
        end
    end
    currentHole = 1
    -- Sparks are used to celebrate the ball going in the hole.
    sparks = {}
    for i=1,8 do
        add(
            sparks,
            {
                x = 0,
                y = 0,
                velX = 0,
                velY = 0,
                t = 0,
            }
        )
    end
    -- Splash particles are used to show you fucked up.
    splashParticles = {}
    for i=1,8 do
        add(
            splashParticles,
            {
                x = 0,
                y = 0,
                velX = 0,
                velY = 0,
                t = 0,
            }
        )
    end
    
    waterTiles = {}
    for x=0, 128 do
        for y=0, 32 do
            local tile = mget(x, y)
            if isInTileset(tile, WATER_TILES) then
                add(
                    waterTiles,
                    { tile = tile, x = x * 8, y = y * 8 }
                )
            end
        end
    end

    initHole(currentHole)
end


local function nextPlayer()
    -- Loop through all players to find the next one
    -- who hasn't finished the hole. If none found,
    -- set to 0.
    local originalPlayer = activePlayer
    while true do
        activePlayer = activePlayer + 1
        if activePlayer > playerCount then
            activePlayer = 1
        end
        if not playerHasCompletedHole[activePlayer] then
            return
        end
        if activePlayer == originalPlayer then
            activePlayer = 0
            return
        end
    end
end


function updateGame()
    if gameStartTimer > 0 then
        gameStartTimer = gameStartTimer - 1
        return
    end

    if nextHoleTimer > 0 then
        nextHoleTimer = nextHoleTimer - 1
        if nextHoleTimer == 0 then
            if currentHole < 16 then
                currentHole = currentHole + 1
                initHole(currentHole)
            else
                roundOver = true
                sfx(SFX.SELECT)
            end
        end
    end

    showingScorecard = false
    if roundOver then
        if btn(5) then
            sfx(SFX.SELECT)
            currentState = STATES.TITLE
            -- return immediately to avoid
            -- doing any premature updating
            -- before gameStartTimer hits 0
            return
        end
    else
        -- Show scorecard
        if btn(4) then
            showingScorecard = true
        end
    end


    if waterTimer > 0 then
        waterTimer = waterTimer - 1
        if waterTimer == 0 then
            balls[activePlayer]:reset(
                ballOrigin.x + 2,
                ballOrigin.y + 2
            )
        end
    end

    -- Update sparks that fly up when ball skims the hole.
    for _, spark in ipairs(sparks) do
        if spark.t > 0 then
            spark.t = spark.t - 1
            spark.x = spark.x + spark.velX
            spark.y = spark.y + spark.velY
            spark.velX = spark.velX * 0.99
            spark.velY = spark.velY * 0.99
        end
    end

    -- Update splash particles that show the ball entering the water
    for _, splashParticle in ipairs(splashParticles) do
        if splashParticle.t > 0 then
            splashParticle.t = splashParticle.t - 1
            splashParticle.x = splashParticle.x + splashParticle.velX
            splashParticle.y = splashParticle.y + splashParticle.velY
            splashParticle.velX = splashParticle.velX * 0.97
            splashParticle.velY = splashParticle.velY * 0.97
        end
    end

    if waterTimer == 0 and activePlayer > 0 and not playerHasCompletedHole[activePlayer] then
        if btn(0) then
            angle = angle + ANGLE_CHANGE_RATE
        elseif btn(1) then
            angle = angle - ANGLE_CHANGE_RATE
        end

        if btnp(5) then
            charging = true
        end

        if charging then
            if btn(5) then
                if powerIncreasing then
                    power = power + POWER_CHANGE_RATE
                else
                    power = power - POWER_CHANGE_RATE
                end
                if power > 1 then
                    power = 1
                    powerIncreasing = false
                elseif power < 0 then
                    power = 0
                    powerIncreasing = true
                end
            elseif power > 0 then
                charging = false
                balls[activePlayer]:hit(angle, power)
                strokePlayed = true
                power = 0
                powerIncreasing = true
                scores[activePlayer][currentHole] = scores[activePlayer][currentHole] + 1

                -- Skew angle slightly so next player can't 'cheat' and use
                -- same angle to get same result.
                angle = angle + rnd(0.2) - 0.1
            end
        end

        balls[activePlayer]:update()

        -- Check for water. sploosh
        local currentTile = mget(
            flr((balls[activePlayer].x + Ball.SIZE/2)/8),
            flr((balls[activePlayer].y + Ball.SIZE/2)/8)
        )
        if isInTileset(currentTile, WATER_TILES) then
            waterTimer = WATER_TIMER_MAX
            sfx(SFX.SPLASH)
            resetSplashParticles(
                balls[activePlayer].x + Ball.SIZE/2,
                balls[activePlayer].y + Ball.SIZE/2
            )
        end

        if balls[activePlayer].isSunk then
            playerHasCompletedHole[activePlayer] = true
            showingScore = true
        end

        -- Regular next player if player doesn't sink the ball.
        -- If the player sinks, this logic is handled after dismissing the score alert.
        if strokePlayed and balls[activePlayer].isStopped and not balls[activePlayer].isSunk then
            nextPlayer()
            strokePlayed = false
        end
    else
        if showingScore and btnp(5) then
            nextPlayer()
            showingScore = false
            sfx(SFX.SELECT)
            strokePlayed = false
            if activePlayer == 0 then
                holeCompleted = true
                nextHoleTimer = NEXT_HOLE_TIMER_MAX
            end
        end
    end
end


local function drawSingleScorecard()
    local x = 0
    local y = 0
    rectfill(20, 40 + 6, 108, 40 + 6, 7)
    rectfill(20, 72 + 6, 108, 72 + 6, 7)
    for holeNumber, score in pairs(scores[1]) do
        print(
            holeNumber,
            22 + x * 10,
            40 + y * 32,
            7
        )
        print(
            score,
            22 + x * 10,
            40 + y * 32 + 8,
            7
        )
        x = x + 1
        if x >= 8 then
            x = 0
            y = y + 1
        end
    end
    -- Add scores onto the ends of rows
    local firstHalfScore = 0
    local secondHalfScore = 0
    for i=1,8 do
        local holeScore = scores[1][i]
        if not holeScore then
            holeScore = 0
        end
        firstHalfScore = firstHalfScore + holeScore
    end
    for i=9,16 do
        local holeScore = scores[1][i]
        if not holeScore then
            holeScore = 0
        end
        secondHalfScore = secondHalfScore + holeScore
    end
    print(firstHalfScore, 102, 48, 7)
    print(secondHalfScore, 102, 80, 7)

    -- Final score
    print('SCORE', (128 - 5 * 4)/2, 92, 7)
    local finalScore = tostring(firstHalfScore + secondHalfScore)
    print(finalScore, (128 - #finalScore * 4)/2, 98, 7)
end

function drawMultiScorecard()
    local totalScores = {}
    for p=1, playerCount do
        local totalScore = 0
        for _, holeScore in ipairs(scores[p]) do
            totalScore = totalScore + holeScore
        end
        totalScores[p] = totalScore
    end

    local winningPlayers= { 1 }
    for p=2, playerCount do
        -- All players in winningPlayers have the same score, so we can
        -- just check the first one to see if this player is better.
        if totalScores[p] < totalScores[winningPlayers[1]] then
            winningPlayers = { p }
        elseif totalScores[p] == totalScores[winningPlayers[1]] then
            add(winningPlayers, p)
        end
    end

    for p=1, playerCount do
        local x = (p - 1) % 2
        local y = flr((p - 1)/2)

        local color = 7
        local playerText = 'Player '..tostring(p)
        if roundOver then
            for _, winningPlayer in ipairs(winningPlayers) do
                if winningPlayer == p then
                    color = 10
                    playerText = 'Champion '..tostring(p)
                    break
                end
            end
        end
        local totalScoreText = tostring(totalScores[p])

        print(
            playerText,
            16 + x * 48 + (48 - #playerText * 4)/2,
            40 + y * 32,
            color
        )

        spr(
            Ball.SPRITES[p],
            16 + x * 48 + (48 - 8)/2,
            48 + y * 32
        )

        print(
            totalScoreText,
            16 + x * 48 + (48 - #totalScoreText * 4)/2,
            58 + y * 32,
            color
        )
    end
end

function drawHud()
    if showingScorecard or roundOver then
        drawBox(8, 8, 112, 12)
        drawBox(8, 20, 112, 100)
        print('scorecard', (128 - 9 * 4)/2, 12, 7)

        if playerCount == 1 then
            drawSingleScorecard()
        else
            drawMultiScorecard()
        end
        
        -- Only offer player next round if round is over, not
        -- if they're checking their scorecard mid-game
        if roundOver then
            drawBox(16, 108, 96, 16)
            local text = "press \x97 to play again"
            print(text, (128 - #text * 4)/2, 114, 7)
        end
    else
        -- Shadow
        rectfill(
            POWER_BAR_X, POWER_BAR_Y,
            POWER_BAR_X + POWER_BAR_WIDTH + 2, POWER_BAR_Y + POWER_BAR_HEIGHT + 3,
            5
        )
        -- White outline
        rectfill(
            POWER_BAR_X, POWER_BAR_Y,
            POWER_BAR_X + POWER_BAR_WIDTH + 2, POWER_BAR_Y + POWER_BAR_HEIGHT + 2,
            7
        )
        -- Red power bar
        rectfill(
            POWER_BAR_X + 1, POWER_BAR_Y + 1,
            POWER_BAR_X + 1 + POWER_BAR_WIDTH * power, POWER_BAR_Y + 1 + POWER_BAR_HEIGHT,
            8
        )
        -- Black unpowered section
        rectfill(
            POWER_BAR_X + 1 + POWER_BAR_WIDTH * power, POWER_BAR_Y + 1,
            POWER_BAR_X + 1 + POWER_BAR_WIDTH, POWER_BAR_Y + 1 + POWER_BAR_HEIGHT,
            0
        )
        -- Shadow text
        print('power', POWER_BAR_X + 1 + (POWER_BAR_WIDTH - 20)/2, POWER_BAR_Y + 2 + (POWER_BAR_HEIGHT - 4)/2, 5)
        -- Actual text
        print('power', POWER_BAR_X + 1 + (POWER_BAR_WIDTH - 20)/2, POWER_BAR_Y + 1 + (POWER_BAR_HEIGHT - 4)/2, 7)

        -- Hole Number
        drawBox(POWER_BAR_MARGIN, POWER_BAR_MARGIN, 32, 10)
        -- Hole number text
        print(
            'Hole '..tostring(currentHole),
            POWER_BAR_MARGIN + 3,
            POWER_BAR_MARGIN + 3,
            7
        )

        -- Player indicator
        if activePlayer > 0 then
            drawBox(35, POWER_BAR_MARGIN, 43, 10)
            print("Player "..tostring(activePlayer), 35 + 3, POWER_BAR_MARGIN + 3, 7)
            spr(Ball.SPRITES[activePlayer], 69, POWER_BAR_MARGIN + 1)
        end

        -- Show score after completing hole
        if showingScore then
            drawBox(57, 57, 14, 14)
            print(scores[activePlayer][currentHole], 63, 62, 7)

            drawBox(20, 82, 88, 16)
            print('press X to continue', (128 - 19 * 4)/2, 88, 7)
        end
    end
end


function drawGame()
    local holeX, holeY = getHolePosition(currentHole)

    local cameraX = holeX * 128
    local cameraY = holeY * 128
    if holeCompleted and not showingScore then
        local nextHoleX, nextHoleY = getHolePosition(currentHole + 1)
        cameraX = holeX * 128 + (nextHoleX - holeX) * 128 * (1 - nextHoleTimer/NEXT_HOLE_TIMER_MAX)
        cameraY = holeY * 128 + (nextHoleY - holeY) * 128 * (1 - nextHoleTimer/NEXT_HOLE_TIMER_MAX)
    end

    camera(cameraX, cameraY)
    map(0, 0, 0, 0, 128, 32)
    -- Add animated water tiles
    for _, waterTile in ipairs(waterTiles) do
        spr(
            WATER_FRAMES[waterTile.tile][flr((waterAnimationFrame/20) % 2) + 1],
            waterTile.x,
            waterTile.y
        )
    end

    -- Draw all other balls, except player's (which might be in the water)
    -- Only draw if at least one stroke as been played (so all balls aren't
    -- drawn on the tee.)
    for i, ball in ipairs(balls) do
        if
            i ~= activePlayer and
            not playerHasCompletedHole[i] and
            scores[i][currentHole] > 0
        then
            ball:draw(i)
        end
    end

    if activePlayer > 0 and gameStartTimer == 0 and not playerHasCompletedHole[activePlayer] and waterTimer == 0 then
        balls[activePlayer]:draw(activePlayer)
        if balls[activePlayer].isStopped then
            line(
                balls[activePlayer].x + Ball.SIZE/2 + ANGLE_INDICATOR_BUFFER * cos(angle),
                balls[activePlayer].y + Ball.SIZE/2 + ANGLE_INDICATOR_BUFFER * sin(angle),
                balls[activePlayer].x + Ball.SIZE/2 + (ANGLE_INDICATOR_BUFFER + ANGLE_INDICATOR_LENGTH) * cos(angle),
                balls[activePlayer].y + Ball.SIZE/2 + (ANGLE_INDICATOR_BUFFER + ANGLE_INDICATOR_LENGTH) * sin(angle),
                7
            )
        end
    end

    for _, spark in ipairs(sparks) do
        if spark.t > 0 then
            local y = spark.y + 16 * sin(0.5 * spark.t/SPARK_LIFE_MAX)
            -- Random fun colour
            local splashColor = SPARK_COLORS[flr(rnd(#SPARK_COLORS)) + 1]
            rectfill(spark.x, y, spark.x + 1, y + 1, splashColor)
        end
    end

    for _, splashParticle in ipairs(splashParticles) do
        if splashParticle.t > 0 then
            local y = splashParticle.y + 8 * sin(0.5 * splashParticle.t/splashParticle.tMax)
            -- Random blue shade
            local splashColor = SPLASH_COLORS[flr(rnd(#SPLASH_COLORS)) + 1]
            rectfill(
                splashParticle.x, y,
                splashParticle.x + 1, y + 1,
                splashColor
            )
        end
    end

    -- Hud drawing; only show hud when game is active
    -- i.e. not under menus or titles.
    camera(0, 0)
    if currentState == STATES.GAME then
        drawHud()
    end
end
-- END GAME

-- START TITLES

local function createTransitionPixels()
    local result = {}
    for x=0,15 do
        for y=0,15 do
            add(result, { x = x, y = y })
        end
    end
    for i = #result, 2, -1 do
        local j = ceil(rnd(i))
        result[i], result[j] = result[j], result[i]
    end
    return result
end

local sceneTransitionPixels = createTransitionPixels()

local titleTimer = 0
local showingInstructions = false
local selectedPlayerCount = 1

local function updateTitles()
    titleTimer = titleTimer + 1
    if titleTimer == 90 then
        -- TODO music, three channels to allow for SFX
        -- music(0, 200)
    end
    if titleTimer > 120 then
        if not showingInstructions then
            if btnp(0) and selectedPlayerCount > 1 then
                sfx(SFX.STROKE)
                selectedPlayerCount = selectedPlayerCount - 1
            elseif btnp(1) and selectedPlayerCount < 4 then
                sfx(SFX.STROKE)
                selectedPlayerCount = selectedPlayerCount + 1
            end

            if btnp(5) then
                currentState = STATES.GAME
                sfx(SFX.SELECT)
                initGame(selectedPlayerCount)
            elseif btnp(4) then
                -- Show instructions
                sfx(SFX.SELECT)
                showingInstructions = true
            end
        else
            if btn(5) or btnp(4) then
                sfx(SFX.SELECT)
                showingInstructions = false
            end
        end
    end
end

local function drawTitles()
    if titleTimer < 90 then
        cls()
    end
    if titleTimer < 60 then
        local logoText = 'ruairi made this'
        print(
            logoText,
            (128 - #logoText * 4)/2,
            62,
            7
        )
    elseif titleTimer >= 90 then
        -- Logo
        drawBox(12, 16, 104, 32)
        spr(
            96,
            (128 - 9 * 8)/2,
            24,
            9,
            2
        )

        if showingInstructions then
            drawBox(4, 64, 120, 52)
            local angleInstructionText = "\x8b \x91 - adjust stroke angle"
            local powerInstructionText = "\x97 (held) - select power"
            local strokeInstructionText = "\x97 (release) - play stroke"
            local scorecardInstructionText = "\x8e - show scorecard"
            print(angleInstructionText, (128 - #angleInstructionText * 4)/2, 70, 7)
            print(powerInstructionText, (128 - #powerInstructionText * 4)/2, 82, 7)
            print(strokeInstructionText, (128 - #strokeInstructionText * 4)/2, 94, 7)
            print(scorecardInstructionText, (128 - #scorecardInstructionText * 4)/2, 106, 7)
        else
            drawBox(4, 64, 120, 52)
            local playersText = "select number of players"
            local selectedPlayerCountText = "\x8b  "..tostring(selectedPlayerCount).."  \x91"
            local startText = "press \x97 to tee off"
            local instructionsText = "press \x8e to see instructions"
            print(playersText, (128 - #playersText * 4)/2, 70, 7)
            print(selectedPlayerCountText, (128 - #selectedPlayerCountText * 4)/2, 82, 10)
            print(startText, (128 - #startText * 4)/2, 94, 7)
            print(instructionsText, (128 - #instructionsText * 4)/2, 106, 7)
        end

        if titleTimer < 120 then
            -- Cool pixelate effect when changing scenes
            local pixelCount = (16 * 16) * (1 - ((titleTimer - 90)/30))
            for i=1,pixelCount do
                rectfill(
                    sceneTransitionPixels[i].x * 8,
                    sceneTransitionPixels[i].y * 8,
                    sceneTransitionPixels[i].x * 8 + 8,
                    sceneTransitionPixels[i].y * 8 + 8,
                    0
                )
            end
        end
    end
end

-- END TITLES

-- START MAIN

function _init()
    palt(0, false)
    palt(14, true)
    currentState = STATES.TITLE
    initGame(1)
    sfx(SFX.SINK)
end

function _update60()
    waterAnimationFrame = waterAnimationFrame + 1
    if currentState == STATES.GAME then
        updateGame()
    elseif currentState == STATES.TITLE then
        updateTitles()
    end
end

function _draw()
    cls()
    drawGame()
    if currentState == STATES.TITLE then
        drawTitles()
    end
end
-- END MAIN
