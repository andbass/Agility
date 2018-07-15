-- 
-- Support for spring interpolation
-- See "https://github.com/David20321/7DFPS/blob/master/UnityProject/Assets/Scripts/AimScript.js", the Spring class for more info
-- I did not come up with this, code adapted from Wolfire's 7Day FPS gamejam entry, Receiver

-- Constructor
--
-- props:
-- strength: General strength of spring
-- damping: Level of damping
Spring = {}

function Spring.New(state, target, props)
    local self = { 
        State = state,
        Target = target,
        Vel = 0,
    }
    table.Merge(self, props)

    setmetatable(self, { __index = Spring })
    return self
end

function Spring:Update()
    local dist = self.Target - self.State

    self.Vel = self.Vel + dist * self.Strength * FrameTime()
    self.Vel = self.Vel * math.pow(self.Damping, FrameTime())
    
    self.State = self.State + self.Vel * FrameTime()
    return self.state
end

function Spring:Dist()
    return math.abs(self.State - self.Target)
end

function Spring:Speed()
    return math.abs(self.Vel)
end

function Spring:Active()
    return self:Speed() > 1e-1
end

function Spring:Reset(state)
    self.State = state
    self.Vel = 0
end

setmetatable(Spring, { __call = Spring.new })
