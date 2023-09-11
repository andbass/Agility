
include "agility/util.lua"
local cvar = include "agility/cvars.lua"

-- Network messages
util.AddNetworkString "LedgeGrabbed"
util.AddNetworkString "LedgeReleased"

util.AddNetworkString "BulletTimeStarted"
util.AddNetworkString "BulletTimeStopped"

-- Client files
AddCSLuaFile "agility/spring.lua"

-- Determines how far or high a ledge can be in order to be grabbale by the player
local ledgeReachUpwards = 40
local ledgeReachOutwards = 15

local ledgeHandGap = 20

local releaseWaitTime = 0.2
local jumpOffPower = 250

local enableWallJump = false
local wallJumpPower = 250
local wallJumpDelay = 0.35

local slideMultiplier = 2.0
local slidingSlowdown = 400
local slidingSlopeBoost = 1000

local shootDodgeSpeed = 580
local shootDodgeUpwardSpeed = 160
local shootDodgeStandUpDelay = 1.5
local shootDodgeSlomoCost = 0.125

local slomoTimescale = 0.2
local slomoShootDodgeTimescale = 0.1
local slomoTransitionSpeed = 10.0
local slomoSpeedMultiplier = 1.2

local slomoDrainRate = 0.1
local slomoKillRecovery = 0.2
local slomoOverchargeAmt = 0.15

local playerDmgTypesToScale = bit.bor(
    DMG_BULLET,
    DMG_BUCKSHOT,
    DMG_SNIPER,
    DMG_MISSILEDEFENSE,
    DMG_SLASH,
    DMG_CLUB,
    DMG_SONIC,
    DMG_DISSOLVE
)

local ledgeImpactSounds = {}
for i = 1, 6 do
    table.insert(ledgeImpactSounds, Sound(Format("physics/flesh/flesh_impact_hard%d.wav", i)))
end

local ledgeVaultSounds = {}
for i = 1, 7 do
    table.insert(ledgeVaultSounds, Sound(Format("physics/body/body_medium_impact_soft%d.wav", i)))
end

local function InWater(ply)
    return bit.band(ply:GetFlags(), FL_INWATER) > 0
end

local function LedgeTrace(ply)
    local camPos = ply:GetShootPos()

    local leftHandTrace = util.TraceHull {
        start = camPos + ply:GetUp() * ledgeReachUpwards - ply:GetRight() * ledgeHandGap * 0.2,
        endpos = camPos + ply:GetForward() * ledgeReachOutwards - ply:GetRight() * ledgeHandGap,

        filter = ply,

        mins = Vector(-16, -16, -16),
        maxs = Vector(16, 16, 16),

        mask = MASK_SOLID,
    }

    local rightHandTrace = util.TraceHull {
        start = camPos + ply:GetUp() * ledgeReachUpwards + ply:GetRight() * ledgeHandGap * 0.2,
        endpos = camPos + ply:GetForward() * ledgeReachOutwards + ply:GetRight() * ledgeHandGap,

        filter = ply,

        mins = Vector(-16, -16, -16),
        maxs = Vector(16, 16, 16),

        mask = MASK_SOLID,
    }

    if not leftHandTrace.Hit or not rightHandTrace.Hit then
        return {
            Hit = false
        }
    end

    if leftHandTrace.StartSolid then
        return rightHandTrace
    elseif rightHandTrace.StartSolid then
        return leftHandTrace
    end

    return leftHandTrace
end

local function IsLedgeDetected(ply, ledgeTrace)
    if not ledgeTrace.Hit then return false end

    local roofTrace = util.TraceHull {
        start = ply:GetPos(),
        endpos = ply:GetPos() + ply:GetUp() * ledgeReachUpwards * 1.2,

        filter = ply,

        mins = Vector(-16, -16, 0),
        maxs = Vector(16, 16, 73),
    }

    if roofTrace.Hit then return false end

    local timeDiff = CurTime() - (ply.ReleaseLedgeTime or 0)
    if timeDiff < releaseWaitTime then return false end

    local isSurfaceLedge = ply:GetUp():Dot(ledgeTrace.HitNormal) > 0.8
    if not isSurfaceLedge then return false end

    local isLedgeHighEnough = ledgeTrace.HitPos.z - ply:GetPos().z > 50
    if not isLedgeHighEnough then return false end

    ply.DirToLedge = (ledgeTrace.HitPos - ply:GetShootPos()):GetNormalized()

    local isPlayerLookingAtLedge = ply:GetAimVector():Dot(ply.DirToLedge) > 0.1
    if not isPlayerLookingAtLedge then return false end

    local isLedgeStable = ledgeTrace.Entity:GetVelocity():LengthSqr() < 100.0 * 100.0
    if not isLedgeStable then return false end

    return true
end

local function DeattachFromLedge(ply)
    ply.GrabbedWorld = false
    ply.GrabbedLedge = false

    ply.ReleaseLedgeTime = CurTime()

    -- Tell client
    net.Start("LedgeReleased")
    net.Send(ply)
end

local function AttachToLedge(ply, ledgeTrace)
    if ledgeTrace.HitWorld then
        ply.GrabbedWorld = true
    elseif ledgeTrace.Entity then
        ply.GrabbedRelativePos = ply:GetPos() - ledgeTrace.Entity:GetPos()
    end

    ply.GrabbedLedge = true
    ply.LedgeTrace = ledgeTrace

    ply.GrabbedPos = ply:GetPos()
    ply.GrabbedTime = CurTime()

    ply.GrabbedDist = (ledgeTrace.HitPos - ply:GetPos()).z

    if ply.GrabbedDist > 70 then
        ply.TimeToCheckVault = CurTime() + ply.GrabbedDist * 0.002
    else
        ply.TimeToCheckVault = CurTime() + ply.GrabbedDist * 0.001
    end

    ply:SetVelocity(-ply:GetVelocity())
    ply:ViewPunch(Angle(-15, 0, 0))

    local sound = table.Random(ledgeImpactSounds)
    ply:EmitSound(sound)

    -- Tell client
    net.Start("LedgeGrabbed")
    net.Send(ply)
end

local function VaultLedge(ply)
    DeattachFromLedge(ply)

    local vaultPower = 125 + math.max(ply.LedgeTrace.HitPos.z - ply.GrabbedPos.z, 0) * 2.6
    local vaultDir = ply.VaultDir or 1

    ply:SetVelocity(-ply:GetVelocity() + ply:GetUp() * vaultPower * 65)
    ply:ViewPunch(Angle(vaultPower * 0.04, -vaultDir * vaultPower * 0.04, vaultDir * vaultPower * 0.04))

    ply.VaultDir = -vaultDir

    local sound = table.Random(ledgeVaultSounds)
    ply:EmitSound(sound)
end

local function JumpOffLedge(ply)
    DeattachFromLedge(ply)

    local upwardsPower = 1 - math.max(ply:GetAimVector():Dot(ply:GetUp()), 0)

    ply:SetVelocity(ply:GetAimVector() * jumpOffPower + ply:GetUp() * jumpOffPower * upwardsPower * 0.75)
    ply:ViewPunch(Angle(-10, 0, 0))
end

local function LedgeTick(ply, moveData)
    if ply.GrabbedWorld then 
        moveData:SetOrigin(ply.GrabbedPos)
        moveData:SetVelocity(Vector(0, 0, 0))
    elseif ply.GrabbedLedge and ply.LedgeTrace.Entity then 
        if IsValid(ply.LedgeTrace.Entity) then
            moveData:SetOrigin(ply.GrabbedRelativePos + ply.LedgeTrace.Entity:GetPos())
            moveData:SetVelocity(ply.LedgeTrace.Entity:GetVelocity())
        else
            DeattachFromLedge(ply) 
        end
    end
end

local function WallJumpTrace(ply, direction)
    ply.LastWallJump = CurTime()

    local tracePos = ply:GetPos() + ply:GetRight() * direction * 16
    return util.TraceHull {
        start = tracePos,
        endpos = tracePos,

        filter = ply,

        mins = ply:OBBMins() * 1.5,
        maxs = ply:OBBMaxs() * 1.5,
    }
end

local function WallJump(ply, wallJumpTrace, direction)
    local jumpDir = (ply:GetRight() * -direction + ply:GetUp()):GetNormalized()

    ply:SetVelocity(Vector(0, 0, -ply:GetVelocity().z) + jumpDir * wallJumpPower + ply:GetUp() * wallJumpPower * 0.1)
    ply:ViewPunch(Angle(-10, 0, 15 * -direction))

    local sound = table.Random(ledgeImpactSounds)
    ply:EmitSound(sound, 100, 150)
end

local function StartSliding(ply)
    ply.IsSliding = true
    ply.TimeToCheckSlide = CurTime() + 0.3

    ply.SlideDir = ply:GetVelocity():GetNormalized()
    ply.RightSlideDir = ply.SlideDir:Cross(ply:GetUp())

    ply.SlideSpeed = ply:GetVelocity():Length() * slideMultiplier
    ply:ViewPunch(Angle(-2, 0, 5))
end

local function StopSliding(ply)
    ply.IsSliding = false
    ply.SlideVel = false
    ply.TimeToCheckSlide = CurTime() + 0.3

    local eyes = ply:EyeAngles()
    eyes.roll = 0

    ply:SetEyeAngles(eyes)
end

local function SlidingTick(ply, moveData)
    moveData:SetForwardSpeed(0)
    moveData:SetSideSpeed(0)

    -- Subtracts forward vector to simulate friction
    local vel = ply.SlideVel or ply.SlideDir * ply.SlideSpeed

    local forwardness = ply:GetForward():Dot(ply.SlideDir)
    local rollDir = ply:GetForward():Dot(ply.RightSlideDir) > 0 and 1 or -1

    local slideRoll = math.deg(math.acos(forwardness)) * 0.25 * rollDir
    local curRoll = ply:EyeAngles().roll
    local newRoll = Lerp(10 * FrameTime(), curRoll, slideRoll)

    local newAngle = Angle(ply:EyeAngles())
    newAngle.roll = newRoll

    ply:SetEyeAngles(newAngle)
    
    -- If our speed gets low due to collision or friction, just stop sliding
    if ply:OnGround() then
        local traceGround = util.TraceLine(util.GetPlayerTrace(ply, Vector(0, 0, -1)))
        local velBoost = slidingSlopeBoost * traceGround.HitNormal:Dot(ply.SlideDir)

        vel = vel + ply.SlideDir * velBoost * FrameTime() - ply.SlideDir * slidingSlowdown * FrameTime()
        if vel:GetNormalized():Dot(ply.SlideDir) < 0 then
            moveData:SetVelocity(Vector())
        else 
            moveData:SetVelocity(vel)
        end

        ply.SlideVel = vel
    end
end

local function StartBulletTime(ply)
    if not game.SinglePlayer() or not ply:Alive() then
        return false
    end

    if ply.BulletTimeAmt <= 0.0 and not ply.IsShootDodging then
        return false
    end 

    ply.BulletTimeActive = true
    ply.TimeToAllowBTEnd = RealTime() + 0.5

    ply.OldWalkSpeed = ply:GetWalkSpeed()
    ply.OldRunSpeed = ply:GetRunSpeed()

    ply:SetWalkSpeed(ply.OldWalkSpeed * slomoSpeedMultiplier)
    ply:SetRunSpeed(ply.OldRunSpeed * slomoSpeedMultiplier)
    if ply:IsSprinting() then
        ply:SetMaxSpeed(ply.OldRunSpeed * slomoSpeedMultiplier)
    end

    ply:AddEFlags(EFL_NO_DAMAGE_FORCES)

    net.Start("BulletTimeStarted")
    net.Send(ply)
    return true
end

local function StopBulletTime(ply)
    if not game.SinglePlayer() or not ply.BulletTimeActive then
        return false
    end

    ply.BulletTimeActive = false
    
    -- Discard any overcharge from NPC kills
    ply.OverchargeBulletTimeAmt = 0.0

    -- Be nice and round up
    -- TODO this is kind of janky
    if ply.BulletTimeAmt >= 0.97 then
        ply.BulletTimeAmt = 1.0
    end

    ply:SetWalkSpeed(ply.OldWalkSpeed)
    ply:SetRunSpeed(ply.OldRunSpeed)
    if ply:IsSprinting() then
        ply:SetMaxSpeed(ply.OldRunSpeed)
    end
    
    if not ply.IsShootDodging then
        ply:RemoveEFlags(EFL_NO_DAMAGE_FORCES)
    end

    net.Start("BulletTimeStopped")
    net.Send(ply)
    return true
end

local function DrainBulletTime(ply, typeToDrain, dt)
    ply[typeToDrain] = ply[typeToDrain] - slomoDrainRate * dt
    ply[typeToDrain] = math.max(ply[typeToDrain], 0.0)
end

local function BulletTimeTick(ply)
    if not game.SinglePlayer() then return end

    local timeScale = game.GetTimeScale()
    local timeScaleTarget = nil
    local timeScaleSpeedMult = 1.0
    local realFrameTime = FrameTime() / timeScale

    local adjustedSlomoTimescale = ply.IsShootDodging and slomoShootDodgeTimescale or slomoTimescale
    if ply.BulletTimeActive and timeScale > adjustedSlomoTimescale then
        if ply.IsShootDodging then
            timeScaleTarget = adjustedSlomoTimescale

            -- To be consistent with normal bullet time, we gain overcharge for kills in shootdodge
            -- so drain the overcharge if we have any
            -- I'm not so sure about this (its just done for the visual for getting kills in slomo)
            if ply.OverchargeBulletTimeAmt > 0.0 then
                DrainBulletTime(ply, "OverchargeBulletTimeAmt", realFrameTime)
            end
        elseif ply.BulletTimeAmt > 0.0 or ply.OverchargeBulletTimeAmt > 0.0 then
            timeScaleTarget = adjustedSlomoTimescale

            local typeToDrain = (ply.OverchargeBulletTimeAmt > 0.0) and "OverchargeBulletTimeAmt" or "BulletTimeAmt"
            DrainBulletTime(ply, typeToDrain, realFrameTime)
        else
            StopBulletTime(ply)
        end
    elseif timeScale < 1.0 then
        timeScaleTarget = 1.0
        timeScaleSpeedMult = 0.5
    end

    -- For inf BT, undo any draining
    if cvar.InfiniteBulletTime:GetBool() then
        ply.BulletTimeAmt = 1.0
    end

    ply:SetNWFloat("BulletTimeAmt", ply.BulletTimeAmt)
    ply:SetNWFloat("OverchargeBulletTimeAmt", ply.OverchargeBulletTimeAmt)

    if timeScaleTarget ~= nil then
        -- Use time scale adjusted FrameTime() on purpose here - provides a nice smoothing effect
        local nextTimeScale = math.Approach(timeScale, timeScaleTarget, slomoTransitionSpeed * timeScaleSpeedMult * FrameTime())
        game.SetTimeScale(nextTimeScale)
    end
end


local function ShootDodge(ply)
    if ply.BulletTimeAmt <= 0.0 then
        return false
    end

    -- Discard any overcharge as soon as a shoot dodge is performed
    ply.OverchargeBulletTimeAmt = 0.0

    ply.BulletTimeAmt = ply.BulletTimeAmt - shootDodgeSlomoCost
    ply.BulletTimeAmt = math.max(ply.BulletTimeAmt, 0.0)

    ply.IsShootDodging = true
    ply.ShootDodgeHitGround = false
    ply.TimeToCheckShootDodgeLiftedOff = CurTime() + 0.3

    local aimDir = ply:GetAimVector()

    aimDir.z = 0
    aimDir:Normalize()

    local rightDir = aimDir:Cross(ply:GetUp())
    rightDir:Normalize()

    local desiredForwardDir = ply:KeyDown(IN_FORWARD) and aimDir or ply:KeyDown(IN_BACK) and -aimDir or Vector(0, 0, 0)
    local desiredRightDir = ply:KeyDown(IN_MOVERIGHT) and rightDir or ply:KeyDown(IN_MOVELEFT) and -rightDir or Vector(0, 0, 0)

    ply.ShootDodgeDir = (desiredForwardDir + desiredRightDir):GetNormalized()
    ply.RightShootDodgeDir = ply.ShootDodgeDir:Cross(ply:GetUp())
    ply.ShootDodgeForwardness = ply.ShootDodgeDir:Dot(ply:GetForward())

    local plyPos = ply:GetPos()
    plyPos.z = plyPos.z + 5

    ply:SetPos(plyPos)

    local bottom, top = ply:GetHullDuck()
    top.z = top.z * 0.025
    bottom.z = 0

    ply:SetHull(bottom, top)
    ply:SetHullDuck(bottom, top)

    ply.OldDuckView = ply:GetViewOffsetDucked()
    ply.OldDuckSpeed = ply:GetCrouchedWalkSpeed()

    ply:SetViewOffsetDucked(ply.OldDuckView * Vector(1, 1, 0.5))

    local shootDodgeVel = ply.ShootDodgeDir * shootDodgeSpeed + ply:GetUp() * shootDodgeUpwardSpeed
    ply:SetVelocity(shootDodgeVel - ply:GetVelocity())

    --ply:ViewPunch(Angle(ply.ShootDodgeDir:Dot(ply:GetForward()) * 5, 0, ply.ShootDodgeDir:Dot(ply:GetRight()) * 15))
    ply:ViewPunch(Angle(0, 0, ply.ShootDodgeDir:Dot(ply:GetRight()) * 15))
    ply:SetCrouchedWalkSpeed(0)

    if not ply.BulletTimeActive then
        StartBulletTime(ply)
    end

    return true
end

local function ShootDodgeHitGround(ply)
    ply.ShootDodgeHitGround = true

    -- In the event shoot dodging ends before player hits ground, reset everything again
    StopBulletTime(ply)

    if InWater(ply) then
        ply.ForceDuckCheckTime = CurTime() + 0.5     
    else
        local vel = ply:GetVelocity()
        ply:SetVelocity(vel * 0.75 - vel) -- Have to subtract `vel` since `SetVelocity` actually adds the new velocity to the old velocity
    end

    local pitchAmt = ply:GetForward():Dot(ply.ShootDodgeDir)
    local rollAmt = ply:GetRight():Dot(ply.ShootDodgeDir)

    ply:ViewPunch(Angle(2.5 * pitchAmt, 0, 7.5 * rollAmt))
end

local function StopShootDodge(ply)
    ply.IsShootDodging = false
    ply.TimeToCheckShootDodge = false
    ply.ShootDodgeLiftedOff = false

    ShootDodgeHitGround(ply)

    local eyes = ply:EyeAngles()
    eyes.roll = 0

    ply:SetEyeAngles(eyes)
    ply:SetCrouchedWalkSpeed(ply.OldDuckSpeed)

    timer.Simple(0.26, function()
        if not InWater(ply) then
            ply:SetPos(ply:GetPos() + Vector(0, 0, 5))
        end

        ply:SetViewOffsetDucked(ply.OldDuckView)

        ply:RemoveEFlags(EFL_NO_DAMAGE_FORCES)
        ply:ResetHull()
    end)
end

local function ShootDodgeTick(ply, moveData)
    moveData:AddKey(IN_DUCK)
    moveData:SetSideSpeed(0)

    if not ply:OnGround() then
        -- TODO why was I doing this?
        --moveData:SetForwardSpeed(math.abs(moveData:GetForwardSpeed()) * ply.ShootDodgeForwardness)
        moveData:SetForwardSpeed(0)
    else
        moveData:SetForwardSpeed(0)
    end

    -- TODO move view tilting code into separate function
    local aimDir = ply:GetAimVector()
    aimDir.z = 0
    aimDir:Normalize()

    local forwardness = math.abs(aimDir:Dot(ply.ShootDodgeDir))
    local rollDir = ply:GetForward():Dot(ply.RightShootDodgeDir) > 0 and -1 or 1

    local dodgeRoll = math.deg(math.acos(forwardness)) * 0.35 * rollDir

    local curRoll = ply:EyeAngles().roll
    local newAngle = Angle(ply:EyeAngles().pitch, ply:EyeAngles().yaw, Lerp(20 * FrameTime(), curRoll, dodgeRoll))

    ply:SetEyeAngles(newAngle)
    ply.ShootDodgeLiftedOff = ply.ShootDodgeLiftedOff or (ply:OnGround() and CurTime() > ply.TimeToCheckShootDodgeLiftedOff)

    if ply:OnGround() and ply.ShootDodgeLiftedOff and not ply.ShootDodgeHitGround then
        ShootDodgeHitGround(ply)
        ply.TimeToCheckShootDodge = CurTime() + shootDodgeStandUpDelay
    end
end

local function PlayerTick(ply, moveData)
    BulletTimeTick(ply)

    if ply.ForceDuckCheckTime then
        if CurTime() > ply.ForceDuckCheckTime then
            ply.ForceDuckCheckTime = nil
        else
            moveData:AddKey(IN_DUCK)
        end
    end

    if ply.GrabbedLedge then
        LedgeTick(ply, moveData)
       
        if ply:KeyDown(IN_SPEED) and ply:KeyDown(IN_FORWARD) and CurTime() > ply.TimeToCheckVault then
            VaultLedge(ply)
        end

        return
    elseif ply.IsShootDodging then
        if (ply.TimeToCheckShootDodge and CurTime() > ply.TimeToCheckShootDodge and not moveData:KeyDown(IN_DUCK))
            or ply:GetMoveType() == MOVETYPE_LADDER or ply:GetMoveType() == MOVETYPE_NOCLIP 
            or ply:WaterLevel() >= 3.0 or not ply:Alive() then
            StopShootDodge(ply)
        else
            ShootDodgeTick(ply, moveData)
        end
    elseif ply.IsSliding then
        if ply:OnGround() and CurTime() > ply.TimeToCheckSlide and (not ply:Crouching() or not ply:KeyDown(IN_DUCK)) then
            StopSliding(ply)
        else
            SlidingTick(ply, moveData)
        end
    elseif not ply:OnGround() and not ply:KeyDown(IN_DUCK) and ply:GetMoveType() ~= MOVETYPE_LADDER and ply:GetMoveType() ~= MOVETYPE_NOCLIP then
        local ledgeTrace = LedgeTrace(ply)

        if IsLedgeDetected(ply, ledgeTrace) then
            AttachToLedge(ply, ledgeTrace)
        end
    end
end

hook.Add("PlayerTick", "agility_PlayerTick", PlayerTick)

hook.Add("PlayerSpawn", "agility_PlayerSpawn", function(ply, transition)
    -- These might be set already if we're loading an engine save game
    -- See the `saverestore` module
    ply.BulletTimeAmt = transition and ply.BulletTimeAmt or 1.0
    ply.OverchargeBulletTimeAmt = transition and ply.OverchargeBulletTimeAmt or 0.0

    timer.Simple(0, function()
        -- Fix eyes in stomach issue when crouching
        ply:SetViewOffsetDucked(Vector(0, 0, 40))

        --ply:SetWalkSpeed(150)
        --ply:SetRunSpeed(250)
        ply:SetWalkSpeed(190)
        ply:SetRunSpeed(320)
        ply:SetCrouchedWalkSpeed(0.5)
        ply:SetJumpPower(math.sqrt(2.0 * physenv.GetGravity():Length() * 21.0))
    end)
end)

hook.Add("PlayerDeath", "agility_PlayerDeath", function(ply, inflictor, attacker)
    StopBulletTime(ply)
end)

hook.Add("KeyPress", "agility_PlayerKeyPress", function(ply, key)
    if ply.GrabbedLedge then 
        if key == IN_DUCK then
            DeattachFromLedge(ply)
        elseif key == IN_JUMP then
            JumpOffLedge(ply)
        end

        return
    end

    if not ply.IsShootDodging then
        if not ply:OnGround() and key == IN_JUMP then
            if ply.IsSlidng then return end -- can't wallkick if sliding

            local isStrafing = ply:KeyDown(IN_MOVELEFT) or ply:KeyDown(IN_MOVERIGHT)
            local timeSinceLastWallJump = CurTime() - (ply.LastWallJump or 0)

            if enableWallJump and isStrafing and timeSinceLastWallJump > wallJumpDelay then
                local direction = ply:KeyDown(IN_MOVELEFT) and 1 or -1
                local wallJumpTrace = WallJumpTrace(ply, direction)

                if wallJumpTrace.Hit then
                    WallJump(ply, wallJumpTrace, direction)
                end
            end

            return
        end

        if key == IN_USE and ply:KeyDown(IN_SPEED) and ply:OnGround() then
            ShootDodge(ply)
        end
    end

    -- Check if ready to start sliding
    if not ply.IsSliding then
        if not ply:OnGround() or ply:Crouching() then return end

        if key == IN_DUCK and ply:KeyDown(IN_SPEED) and ply:KeyDown(IN_FORWARD) then
            StartSliding(ply)
            return
        end
    elseif key == IN_JUMP then
        StopSliding(ply)
        return
    end
end)

hook.Add("PlayerUse", "agility_UseShootdodgeCheck", function(ply, ent)
    if ply.IsShootDodging then
        return false
    end
end)

local function CanPlayerPickup(ply, ent)
    return IsValid(ent) and not ent.Dissolving
end

hook.Add("PlayerCanPickupWeapon", "agility_CanPickupWeapon", CanPlayerPickup)
hook.Add("PlayerCanPickupItem", "agility_CanPickupItem", CanPlayerPickup)

hook.Add("OnNPCKilled", "agility_NPCKilled", function(npc, inflictor)
    for i, ply in ipairs(player.GetAll()) do
        if npc:Disposition(ply) == D_HT then
            if ply == inflictor then
                ply.BulletTimeAmt = ply.BulletTimeAmt + slomoKillRecovery
                ply.BulletTimeAmt = math.min(ply.BulletTimeAmt, 1.0)

                -- Hack - if we have almost full BT just round it up
                if ply.BulletTimeAmt >= 0.95 then
                    ply.BulletTimeAmt = 1.0
                end

                -- Allow for a temporary overcharge for kills in bullet time
                if ply.BulletTimeActive then
                    ply.OverchargeBulletTimeAmt = ply.OverchargeBulletTimeAmt + slomoOverchargeAmt
                    ply.OverchargeBulletTimeAmt = math.min(ply.OverchargeBulletTimeAmt, 1.0)
                end
            end
        end
    end

    local function Dissolve(wep, type)
        local dissolverEnt = ents.Create("env_entity_dissolver")
        timer.Simple(5, function()
            if IsValid(dissolverEnt) then
                dissolverEnt:Remove()
            end
        end)
    
        dissolverEnt.Target = "dissolve" .. wep:EntIndex()  
        dissolverEnt:SetKeyValue("dissolvetype", type)
        dissolverEnt:SetKeyValue("magnitude", 0)
        dissolverEnt:SetPos(npc:GetPos())
        dissolverEnt:Spawn()

        wep:SetName(dissolverEnt.Target)

        dissolverEnt:Fire("Dissolve", dissolverEnt.Target, 0)
        dissolverEnt:Fire("Kill", "", 0.1)
    end

    if cvar.DisintegrateDroppedWeapons:GetBool() then
        local nearbyEntities = ents.FindInSphere(npc:GetPos(), 100)
        for i, entity in ipairs(nearbyEntities) do
            if entity:GetOwner() == npc and not entity:IsNPC() and entity:GetClass() ~= "npc_grenade_frag" and entity:GetClass() ~= "raggib" then
                entity.Dissolving = true
                Dissolve(entity, 0)
            end
        end
    end
end)

-- TODO rename hook
hook.Add("EntityTakeDamage", "agility_ScalePlayerDamage", function(ent, dmgInfo)
    local inflictor = dmgInfo:GetInflictor()
    local owner = inflictor:GetOwner()

    if inflictor:GetClass():find("mg_") == 1 then
        dmgInfo:ScaleDamage(cvar.ModernWarfareDamageMultiplier:GetFloat())
    end

    local dmgType = dmgInfo:GetDamageType()
    if ent:IsPlayer() and bit.band(playerDmgTypesToScale, dmgType) > 0 then
        dmgInfo:ScaleDamage(cvar.PlayerDamageMultiplier:GetFloat())
    elseif ent:IsNPC() and (inflictor:IsPlayer() or (IsValid(owner) and owner:IsPlayer())) then
        dmgInfo:ScaleDamage(cvar.NpcDamageMultiplier:GetFloat())
    end
end)

hook.Add("OnEntityCreated", "agility_ScaleNPCHealth", function(ent)
    if ent:IsNPC() then
        -- `Activate()` can result in health getting set, so adjust it on the next tick
        timer.Simple(0.01, function()
            if IsValid(ent) then
                ent:SetMaxHealth(ent:GetMaxHealth() * cvar.NpcHealthMultiplier:GetFloat())
                ent:SetHealth(ent:Health() * cvar.NpcHealthMultiplier:GetFloat())
            end
        end)
    end
end)

concommand.Add("bullet_time", function(ply, cmd, args)
    if not ply.BulletTimeActive and not ply.IsShootDodging then
        StartBulletTime(ply)
    elseif ply.TimeToAllowBTEnd and (RealTime() > ply.TimeToAllowBTEnd) then
        StopBulletTime(ply)
    end
end)

concommand.Add("strip_weapons", function(ply, cmd, args)
    ply:StripWeapons()
end)