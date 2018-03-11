
-- Client files
AddCSLuaFile("agility/spring.lua")

-- Determines how far or high a ledge can be in order to be grabbale by the player
local ledgeReachUpwards = 40
local ledgeReachOutwards = 15

local ledgeHandGap = 20

local releaseWaitTime = 0.2

local jumpOffPower = 250
local wallJumpPower = 300
local slideMultiplier = 1.5

local slidingSlowdown = 100
local slidingSlopeBoost = 500

local shootDodgeTimescale = 0.15
local shootDodgeSpeed = 425
local shootDodgeUpwardSpeed = 275
local shootDodgeStandUpDelay = 1

local ledgeImpactSounds = {}
for i = 1, 6 do
    table.insert(ledgeImpactSounds, Sound(Format("physics/flesh/flesh_impact_hard%d.wav", i)))
end

local ledgeVaultSounds = {}
for i = 1, 7 do
    table.insert(ledgeVaultSounds, Sound(Format("physics/body/body_medium_impact_soft%d.wav", i)))
end

local enemies = {}

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

    local timeDiff = CurTime() - (ply.ReleaseLedgeTime or 0)

    local isSurfaceLedge = ply:GetUp():Dot(ledgeTrace.HitNormal) > 0.8
    local isLedgeHighEnough = ledgeTrace.HitPos.z - ply:GetPos().z > 50

    ply.DirToLedge = (ledgeTrace.HitPos - ply:GetShootPos()):GetNormalized()

    local isPlayerLookingAtLedge = ply:GetAimVector():Dot(ply.DirToLedge) > 0.1

    return timeDiff > releaseWaitTime 
        and not roofTrace.Hit 
        and ledgeTrace.Hit 
        and not ply:Crouching() 
        and isSurfaceLedge 
        and isLedgeHighEnough 
        and isPlayerLookingAtLedge
end

local function DeattachFromLedge(ply)
    ply.GrabbedWorld = false
    ply.GrabbedLedge = false

    ply.ReleaseLedgeTime = CurTime()
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
        ply.TimeToCheckVault = CurTime()
    end

    ply:SetVelocity(-ply:GetVelocity())
    ply:ViewPunch(Angle(-15, 0, 0))

    local sound = table.Random(ledgeImpactSounds)
    ply:EmitSound(sound)
end

local function VaultLedge(ply)
    DeattachFromLedge(ply)

    local vaultPower = 100 + math.max(ply.LedgeTrace.HitPos.z - ply.GrabbedPos.z, 0) * 2.5
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
        moveData:SetOrigin(ply.GrabbedRelativePos + ply.LedgeTrace.Entity:GetPos())
        moveData:SetVelocity(ply.LedgeTrace.Entity:GetVelocity())
    end
end

local function WallJumpTrace(ply, direction)
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
    ply:ViewPunch(Angle(-10, 0, 0))
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
    -- Subtracts forward vector to simulate friction
    local vel = ply.SlideVel or ply.SlideDir * ply.SlideSpeed

    if ply:OnGround() then
        local traceGround = util.TraceLine(util.GetPlayerTrace(ply, Vector(0, 0, -1)))
        local velBoost = slidingSlopeBoost * traceGround.HitNormal:Dot(ply.SlideDir)

        vel = vel + ply.SlideDir * velBoost * FrameTime() - ply.SlideDir * slidingSlowdown * FrameTime()
    else 
        ply.SlideTime = CurTime()
    end

    local forwardness = ply:GetForward():Dot(ply.SlideDir)
    local rollDir = ply:GetForward():Dot(ply.RightSlideDir) > 0 and 1 or -1

    local slideRoll = math.deg(math.acos(forwardness)) * 0.25 * rollDir

    local curRoll = ply:EyeAngles().roll
    local newAngle = Angle(ply:EyeAngles().pitch, ply:EyeAngles().yaw, Lerp(10 * FrameTime(), curRoll, slideRoll))

    ply:SetEyeAngles(newAngle)
    
    -- If our speed gets low due to collision or friction, just stop sliding
    if vel:GetNormalized():Dot(ply.SlideDir) < 0 then
        moveData:SetVelocity(Vector())
    else 
        moveData:SetVelocity(vel)
    end

    ply.SlideVel = vel
end

local function ShootDodge(ply)
    ply.IsShootDodging = true
    ply.TimeToCheckShootDodgeLiftedOff = CurTime() + 0.3

    local desiredForwardDir = ply:KeyDown(IN_FORWARD) and ply:GetForward() or ply:KeyDown(IN_BACK) and -ply:GetForward() or Vector(0, 0, 0)
    local desiredRightDir = ply:KeyDown(IN_MOVERIGHT) and ply:GetRight() or ply:KeyDown(IN_MOVELEFT) and -ply:GetRight() or Vector(0, 0, 0)

    ply.ShootDodgeDir = (desiredForwardDir + desiredRightDir):GetNormalized()
    ply.RightShootDodgeDir = ply.ShootDodgeDir:Cross(ply:GetUp())
    ply.ShootDodgeForwardness = ply.ShootDodgeDir:Dot(ply:GetForward())

    local plyPos = ply:GetPos()
    plyPos.z = plyPos.z + 1

    ply:SetPos(plyPos)

    local bottom, top = ply:GetHullDuck()
    top.z = top.z * 0.25
    bottom.z = 1

    ply:SetHull(bottom, top)
    ply:SetHullDuck(bottom, top)

    ply.OldDuckView = ply:GetViewOffsetDucked()
    ply.OldDuckSpeed = ply:GetCrouchedWalkSpeed()

    ply:SetViewOffsetDucked(ply.OldDuckView * Vector(1, 1, 0.5))

    local shootDodgeVel = ply.ShootDodgeDir * shootDodgeSpeed + ply:GetUp() * shootDodgeUpwardSpeed

    ply:SetVelocity(shootDodgeVel - ply:GetVelocity())

    ply:ViewPunch(Angle(ply.ShootDodgeDir:Dot(ply:GetForward()) * 5, 0, ply.ShootDodgeDir:Dot(ply:GetRight()) * 15))
    ply:SetCrouchedWalkSpeed(0)

    -- Update enemy accuracy
    for i, npc in ipairs(ply.Enemies) do
        npc.OldAccuracy = npc:GetCurrentWeaponProficiency()
        npc:SetCurrentWeaponProficiency(0)
    end

    ply.OldTimeScale = game.GetTimeScale()
    game.SetTimeScale(shootDodgeTimescale)
end

local function ShootDodgeHitGround(ply)
    -- In the event shoot dodging ends before player hits ground, reset everything again
    game.SetTimeScale(ply.OldTimeScale)

    for i, npc in ipairs(ply.Enemies) do
        if npc.OldAccuracy then
            npc:SetCurrentWeaponProficiency(npc.OldAccuracy)
        end
    end
end

local function ShootDodgeTick(ply, moveData)
    moveData:AddKey(IN_DUCK)
    moveData:SetSideSpeed(0)

    if not ply:OnGround() then
        moveData:SetForwardSpeed(math.abs(moveData:GetForwardSpeed()) * ply.ShootDodgeForwardness)
    else 
        moveData:SetForwardSpeed(0)
    end

    -- TODO move view tilting code into seperate function
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

    if ply:OnGround() and ply.ShootDodgeLiftedOff then
        ShootDodgeHitGround(ply)
        ply.TimeToCheckShootDodge = ply.TimeToCheckShootDodge or CurTime() + shootDodgeStandUpDelay
    end
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
        ply:SetPos(ply:GetPos() + Vector(0, 0, 5))
        ply:SetViewOffsetDucked(ply.OldDuckView)

        ply:ResetHull()
    end)
end

local function PlayerTick(ply, moveData)
    if ply.GrabbedLedge then
        LedgeTick(ply, moveData)
        
        if ply:KeyDown(IN_SPEED) and ply:KeyDown(IN_FORWARD) and CurTime() > ply.TimeToCheckVault then
            VaultLedge(ply)
        end

        return
    elseif ply.IsShootDodging then
        if (ply.TimeToCheckShootDodge and CurTime() > ply.TimeToCheckShootDodge) or ply:GetMoveType() == MOVETYPE_LADDER or ply:WaterLevel() > 0 or ply:GetMoveType() == MOVETYPE_NOCLIP then
            StopShootDodge(ply)
        else
            ShootDodgeTick(ply, moveData)
        end
    end

    if not ply:OnGround() and ply:GetMoveType() ~= MOVETYPE_LADDER and ply:GetMoveType() ~= MOVETYPE_NOCLIP then
        local ledgeTrace = LedgeTrace(ply)

        if IsLedgeDetected(ply, ledgeTrace) then
            AttachToLedge(ply, ledgeTrace)
        end
    elseif ply:OnGround() then
        if ply.IsSliding then
            if CurTime() > ply.TimeToCheckSlide and (not ply:Crouching() or not ply:KeyDown(IN_DUCK)) then
                StopSliding(ply)
            else 
                SlidingTick(ply, moveData)
            end
        end
    end
end

local function UpdateEnemiesForPlayer(ply)
    for i, ent in ipairs(ents.FindByClass("npc_*")) do
        if ent:IsNPC() and ent:Disposition(ply) == D_HT then
            table.insert(ply.Enemies, ent)
        end
    end
end

hook.Add("PlayerTick", "agility_PlayerTick", PlayerTick)

hook.Add("PlayerSpawn", "agility_PlayerSpawn", function(ply)
    ply.Enemies = {}
    UpdateEnemiesForPlayer(ply)
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

    if not ply:OnGround() and key == IN_JUMP and (ply:KeyDown(IN_MOVELEFT) or ply:KeyDown(IN_MOVERIGHT)) then
        local direction = ply:KeyDown(IN_MOVELEFT) and 1 or -1
        local wallJumpTrace = WallJumpTrace(ply, direction)

        if wallJumpTrace.Hit then
            WallJump(ply, wallJumpTrace, direction)
        end
    elseif not ply.IsSliding and ply:OnGround() and not ply:Crouching() and key == IN_DUCK and ply:KeyDown(IN_SPEED) and ply:KeyDown(IN_FORWARD) then 
        StartSliding(ply)
    elseif ply.IsSliding and key == IN_JUMP then
        StopSliding(ply)
    elseif not ply.IsShootDodging and key == IN_USE and ply:KeyDown(IN_SPEED) and ply:OnGround() then
        ShootDodge(ply)
    end
end)

hook.Add("OnEntityCreated", "agility_EntityCreation", function(ent)
    if ent:IsNPC() then
        for i, ply in ipairs(player.GetAll()) do
            if ent:Disposition(ply) == D_HT then
                table.insert(ply.Enemies, ent)
            end
        end
    end
end)

hook.Add("EntityRemoved", "agility_EntityRemoved", function(ent)
    if ent:IsNPC() then
        for i, ply in ipairs(player.GetAll()) do
            if ent:Disposition(ply) == D_HT then
                table.RemoveByValue(ply.Enemies, ent)
            end
        end
    end
end)

hook.Add("OnNPCKilled", "agility_NPCKilled", function(npc)
    for i, ply in ipairs(player.GetAll()) do
        if npc:Disposition(ply) == D_HT then
            table.RemoveByValue(ply.Enemies, npc)
        end
    end
end)
