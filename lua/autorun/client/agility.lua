
include "agility/util.lua"
include "agility/spring.lua"

local shootSpringResetDelay = 0.75

local spring = Spring.New(0, 0, {
    Strength = 200.0,
    Damping = 0.0001,
})

net.Receive("LedgeGrabbed", function()
    spring.Target = 1
end)

net.Receive("LedgeReleased", function()
    spring.Target = 0
end)

function GetDefaultView(weapon, vm, oldPos, oldAng, pos, ang)
    local pos, ang = Vector(pos), Angle(ang)

    local viewFunc = weapon.GetViewModelPosition
    if viewFunc then
        local newPos, newAng = viewFunc(weapon, pos, ang)

        pos = newPos or pos
        ang = newAng or ang
    end

    -- MAYBE_TODO support SWEP:CalcViewModelView?

    return pos, ang
end

function ViewModelLedgeGrabView(pos, ang)
    newPos = pos - ang:Up() * 20

    newAng = Angle(ang)
    newAng:RotateAroundAxis(ang:Up(), 10)
    newAng:RotateAroundAxis(ang:Right(), 40)

    return newPos, newAng
end

function ViewModelLedgeGrab(weapon, vm, oldPos, oldAng, pos, ang)
    local ply = LocalPlayer()
    spring:Update()

    if ply:KeyDown(IN_ATTACK) or ply:KeyDown(IN_ATTACK2) then
        ply.LastAttack = CurTime()
    end

    if ply.LastAttack and CurTime() - ply.LastAttack < shootSpringResetDelay then
        spring:Reset(0)
    end

    pos, ang = GetDefaultView(weapon, vm, oldPos, oldAng, pos, ang)
    local newPos, newAng = ViewModelLedgeGrabView(pos, ang)

    local interpPos = LerpVector(spring.State, pos, newPos)
    local interpAng = LerpAngle(spring.State, ang, newAng)

    return interpPos, interpAng
end

hook.Add("CalcViewModelView", "agility_cl_ViewModel", ViewModelLedgeGrab)
