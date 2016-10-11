
-- Determines how far or high a ledge can be in order to be grabbale by the player
local ledgeReachUpwards = 40
local ledgeReachOutwards = 10

local releaseWaitTime = 0.2

local jumpOffPower = 300
local wallJumpPower = 300

local ledgeImpactSounds = {}
for i = 1, 6 do
    table.insert(ledgeImpactSounds, Sound(Format("physics/flesh/flesh_impact_hard%d.wav", i)))
end

local ledgeVaultSounds = {}
for i = 1, 7 do
    table.insert(ledgeVaultSounds, Sound(Format("physics/body/body_medium_impact_soft%d.wav", i)))
end

local function LedgeTrace(ply)
    local camPos = ply:GetShootPos()

    return util.TraceHull {
        start = camPos + ply:GetUp() * ledgeReachUpwards,
        endpos = camPos + ply:GetForward() * ledgeReachOutwards,

        filter = ply,

        mins = Vector(-16, -16, -16),
        maxs = Vector(16, 16, 16),

        mask = MASK_ALL,
    }
end

local function IsLedgeDetected(ply, ledgeTrace)
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

    return timeDiff > releaseWaitTime and not roofTrace.Hit and ledgeTrace.Hit and not ply:Crouching() and isSurfaceLedge and isLedgeHighEnough and isPlayerLookingAtLedge
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
        ply.VaultDelay = CurTime() + ply.GrabbedDist * 0.002
    else
        ply.VaultDelay = CurTime()
    end

    ply:SetVelocity(-ply:GetVelocity())
    ply:ViewPunch(Angle(-15, 0, 0))

    local sound = table.Random(ledgeImpactSounds)
    ply:EmitSound(sound)
end

local function WallJumpTrace(ply, direction)
    local tracePos = ply:GetPos() + ply:GetRight() * direction * 16
    return util.TraceHull {
        start = tracePos,
        endpos = tracePos,

        filter = ply,

        mins = ply:OBBMins() * 1.25,
        maxs = ply:OBBMaxs() * 1.25,
    }
end

local function WallJump(ply, wallJumpTrace, direction)
    local jumpDir = (ply:GetRight() * -direction + ply:GetUp() * 1.5):GetNormalized()

    ply:SetVelocity(Vector(0, 0, -ply:GetVelocity().z) + jumpDir * wallJumpPower)
    ply:ViewPunch(Angle(-10, 0, 15 * -direction))

    local sound = table.Random(ledgeImpactSounds)
    ply:EmitSound(sound, 100, 150)
end

local function VaultLedge(ply)
    DeattachFromLedge(ply)

    local vaultPower = 100 + math.max(ply.LedgeTrace.HitPos.z - ply.GrabbedPos.z, 0) * 2.5
    local vaultDir = ply.VaultDir or 1

    ply:SetVelocity(-ply:GetVelocity() + ply:GetUp() * vaultPower * 65)
    ply:ViewPunch(Angle(vaultPower * 0.03, -vaultDir * vaultPower * 0.04, vaultDir * vaultPower * 0.03))

    ply.VaultDir = -vaultDir

    local sound = table.Random(ledgeVaultSounds)
    ply:EmitSound(sound)
end

-- TODO make camera look better
local function StartSliding(ply)
    ply.IsSliding = true

    ply.SlideTime = CurTime()
    ply.TimeToCheckSlide = CurTime() + 0.3

    ply.SlideDir = ply:GetForward()
    ply.RightSlideDir = ply:GetForward():Cross(ply:GetUp())

    ply.SlideSpeed = ply:GetVelocity():Length() * 1.25

    ply:ViewPunch(Angle(10, 0, 0))
end

local function StopSliding(ply)
    ply.IsSliding = false

    ply:ViewPunch(Angle(0, 0, -10))
    timer.Simple(0.3, function()
        local eyeAngles = ply:EyeAngles()
        eyeAngles.roll = 0

        ply:SetEyeAngles(eyeAngles)
    end)
end

local function PlayerTick(ply, moveData)
    if ply.GrabbedLedge then
        if ply.GrabbedWorld then 
            moveData:SetOrigin(ply.GrabbedPos)
            moveData:SetVelocity(Vector(0, 0, 0))
        elseif ply.GrabbedLedge and ply.LedgeTrace.Entity then 
            moveData:SetOrigin(ply.GrabbedRelativePos + ply.LedgeTrace.Entity:GetPos())
            moveData:SetVelocity(ply.LedgeTrace.Entity:GetVelocity())
        end
        
        if ply:KeyDown(IN_SPEED) and ply:KeyDown(IN_FORWARD) and CurTime() > ply.VaultDelay then
            VaultLedge(ply)
        end

        return
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
                moveData:SetVelocity(ply.SlideDir * ply.SlideSpeed - slowDown)
            end

            local forwardness = ply:GetForward():Dot(ply.SlideDir)
            local rollDir = ply:GetForward():Dot(ply.RightSlideDir) > 0 and 1 or -1

            local rollAngle = math.deg(math.acos(forwardness)) * 0.25 * rollDir
            ply:SetEyeAngles(Angle(ply:EyeAngles().pitch, ply:EyeAngles().yaw, 0) + Angle(0, 0, rollAngle))
        end
    end
end

local function JumpOffLedge(ply)
    DeattachFromLedge(ply)

    local upwardsPower = 1 - math.max(ply:GetAimVector():Dot(ply:GetUp()), 0)

    ply:SetVelocity(ply:GetAimVector() * jumpOffPower + ply:GetUp() * jumpOffPower * upwardsPower * 0.75)
    ply:ViewPunch(Angle(-10, 0, 0))
end

hook.Add("PlayerTick", "agility_PlayerTick", PlayerTick)

hook.Add("KeyPress", "agility_KegPress", function(ply, key)
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
    elseif ply:OnGround() and not ply:Crouching() and key == IN_DUCK and ply:KeyDown(IN_SPEED) and ply:KeyDown(IN_FORWARD) then 
        StartSliding(ply)
    elseif ply.IsSliding and key == IN_JUMP then
        StopSliding(ply)
    end
end)
