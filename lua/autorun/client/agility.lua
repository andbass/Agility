
include "agility/util.lua"
include "agility/spring.lua"

local cvar = include "agility/cvars.lua"

---
-- Ledge Grab View Model Stuff
---

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

local function GetDefaultView(weapon, vm, oldPos, oldAng, pos, ang)
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

local function ViewModelLedgeGrabView(pos, ang)
    local newPos = pos - ang:Up() * 20
    local newAng = Angle(ang)

    newAng:RotateAroundAxis(ang:Up(), 10)
    newAng:RotateAroundAxis(ang:Right(), -20)

    return newPos, newAng
end

local function ViewModelLedgeGrab(weapon, vm, oldPos, oldAng, pos, ang)
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

    return pos, interpAng
end

--hook.Add("CalcViewModelView", "agility_cl_ViewModel", ViewModelLedgeGrab)

---
-- Kill feed disable
---
local deathnoticeTime = GetConVar("hud_deathnotice_time")
local oldDeathnoticeTime = 0

local function EnableKillFeed(enable)
    if tobool(enable) then
        RunConsoleCommand(deathnoticeTime:GetName(), oldDeathnoticeTime)
    else
        oldDeathnoticeTime = deathnoticeTime:GetInt()
        RunConsoleCommand(deathnoticeTime:GetName(), 0)
    end
end

hook.Add("InitPostEntity", "agility_cl_Init", function()
    EnableKillFeed(not cvar.HideKillFeedInSP:GetBool())
end)

cvars.AddChangeCallback(cvar.HideKillFeedInSP:GetName(), function(convar, old, new)
    EnableKillFeed(not new)
end)

---
-- Bullet Time HUD
---
local bulletTimeActive = false

local bulletTimeWidth = 0.1
local bulletTimeHeight = 0.015
local bulletTimeMargin = 0.005

local bulletTimeOuterColor = Color(0, 0, 0, 128)
local bulletTimeInnerColor = Color(200, 200, 200, 200)
--local bulletTimeInnerOverchargeColor = Color(255, 255, 255, 200)
local bulletTimeInnerOverchargeColor = Color(255, 220, 0, 200)

local overchargeGainColorSpeed = 2.0
local overchargeLoseColorSpeed = 0.25
local overchargeThresholdAmt = 0.2

local maxBulletTimeAmt = 0.0
local overchargeColorProgress = 0.0

local bulletTimeAlphaShowSpeed = 4.0
local bulletTimeAlphaHideSpeed = 1.0
local bulletTimeMaxAlpha  = 1.5 -- Let this go above 1.0 - keeps the BT bar on screen for a bit before fading

local bulletTimeAlphaProgress = bulletTimeMaxAlpha

local function LerpColor(frac, col1, col2)
    frac = math.Clamp(frac, 0.0, 1.0)
    return Color(
        Lerp(frac, col1.r, col2.r),
        Lerp(frac, col1.g, col2.g),
        Lerp(frac, col1.b, col2.b),
        Lerp(frac, col1.a, col2.a)
    )
end

local function ColorAlphaMult(baseCol, alphaMult)
    alphaMult = math.Clamp(alphaMult, 0.0, 1.0)
    return Color(baseCol.r, baseCol.g, baseCol.b, baseCol.a * alphaMult)
end

net.Receive("BulletTimeStarted", function()
    local ply = LocalPlayer()

    bulletTimeActive = true
    ply.BulletTimeActive = true

    surface.PlaySound("agility/bt_start.wav")

    timer.Create("agility_BulletTimeSoundLoop", 0.25, 0, function()
        if bulletTimeActive then
            surface.PlaySound("agility/bt_loop.wav")
        end
    end)
end)

net.Receive("BulletTimeStopped", function()
    local ply = LocalPlayer()

    bulletTimeActive = false
    ply.BulletTimeActive = false

    timer.Stop("agility_BulletTimeSoundLoop")
    surface.PlaySound("agility/bt_end.wav")
end)

hook.Add("HUDPaint", "agility_cl_HUDPaint", function()
    -- If infinite BT is on, there is no point to showing the BT bar
    if cvar.InfiniteBulletTime:GetBool() then
        return
    end

    local ply = LocalPlayer()
    local btAmt = ply:GetNWFloat("BulletTimeAmt")
    local currOverchargeAmt = ply:GetNWFloat("OverchargeBulletTimeAmt")

    -- Needed for both inner and outer rects - just compute it first
    local btAlphaTarget = (game.SinglePlayer() and ply:Alive() and (bulletTimeActive or btAmt < 1.0))
        and bulletTimeMaxAlpha or 0.0
    local btAlphaSpeed = (bulletTimeAlphaProgress < btAlphaTarget) and bulletTimeAlphaShowSpeed or bulletTimeAlphaHideSpeed
    bulletTimeAlphaProgress = math.Approach(bulletTimeAlphaProgress, btAlphaTarget, btAlphaSpeed * RealFrameTime())

    if bulletTimeAlphaProgress <= 0.0 then
        return
    end

    local btWidthPx = bulletTimeWidth * ScrW() 
    local btHeightPx = bulletTimeHeight * ScrH() 
    local btMarginPx = bulletTimeMargin * ScrH()

    local centerX = ScrW() / 2
    local btX = centerX - (btWidthPx / 2)
    local btY = ScrH() - btMarginPx - btHeightPx
    draw.RoundedBox(5, btX, btY, btWidthPx, btHeightPx, ColorAlphaMult(bulletTimeOuterColor, bulletTimeAlphaProgress))

    local btInnerMarginPx = 4
    local btInnerWidthPx = btWidthPx - btInnerMarginPx * 2
    local btInnerHeightPx = btHeightPx - btInnerMarginPx * 2

    local btInnerX = btX + btInnerMarginPx
    local btInnerY = btY + btInnerMarginPx

    -- Account for overcharge
    local overchargeColorSpeed = (overchargeColorProgress < currOverchargeAmt) and overchargeGainColorSpeed or overchargeLoseColorSpeed
    overchargeColorProgress = math.Approach(overchargeColorProgress, currOverchargeAmt, overchargeColorSpeed * RealFrameTime())

    local btInnerColor = LerpColor(overchargeColorProgress / overchargeThresholdAmt, bulletTimeInnerColor, bulletTimeInnerOverchargeColor)
    draw.RoundedBox(5, btInnerX, btInnerY, btInnerWidthPx * btAmt, btInnerHeightPx, ColorAlphaMult(btInnerColor, bulletTimeAlphaProgress))
end)

---
-- Bullet Time Effects
---
local lastBulletTimeActive = bulletTimeActive
local bulletTimeEffectsAmt = 0.0
local bulletTimeEffectsGainSpeed = 8.5
local bulletTimeEffectsLoseSpeed = 1.0

local matOverlay = Material("effects/flicker_256")
local matVignette = Material("effects/grey")
local matBlack = Material("effects/black")

local blinkDuration = 0.2
local blinkEndTime = nil

local function DrawOverlay()
    render.UpdateScreenEffectTexture()

    matOverlay:SetFloat("$alpha", 0.75 * bulletTimeEffectsAmt)
    matOverlay:SetVector("$color", Vector(1.0, 0.92, 1.0))
    render.SetMaterial(matOverlay)
    render.DrawScreenQuad(true)

    matVignette:SetFloat("$alpha", 0.9 * bulletTimeEffectsAmt)
    render.SetMaterial(matVignette)
	render.DrawScreenQuad(true)
end

local function DrawBlink()
    local timeLeft = blinkEndTime - RealTime()
    local blinkPeak = blinkDuration / 2.0
    
    -- Half way through the blink the screen is fully black
    local timeTilPeak = math.abs(timeLeft - blinkPeak)
    local alpha = 1.0 - (timeTilPeak / blinkPeak)

    matBlack:SetFloat("$alpha", alpha)
    render.SetMaterial(matBlack)
	render.DrawScreenQuad(true)
end

hook.Add("RenderScreenspaceEffects", "agility_cl_RenderScreenspaceEffects", function()
    local btEffectsTarget = bulletTimeActive and 1.0 or 0.0

    local btEffectsSpeed = (bulletTimeEffectsAmt < btEffectsTarget) and bulletTimeEffectsGainSpeed or bulletTimeEffectsLoseSpeed
    bulletTimeEffectsAmt = math.Approach(bulletTimeEffectsAmt, btEffectsTarget, btEffectsSpeed * RealFrameTime())

    if not lastBulletTimeActive and bulletTimeActive then
        blinkEndTime = RealTime() + blinkDuration
    end

    if blinkEndTime and RealTime() <= blinkEndTime then
        DrawBlink()
    end

    if bulletTimeEffectsAmt > 0.0 then
        DrawSharpen(1.0, bulletTimeEffectsAmt)
        DrawOverlay()
    end

    lastBulletTimeActive = bulletTimeActive
end)

local bulletTimeBlur = 0.1

hook.Add("GetMotionBlurValues", "agility_cl_GetMotionBlurValues", function(hor, vert, forward, rot)
    return hor, vert, forward + bulletTimeBlur * bulletTimeEffectsAmt, rot
end)

hook.Add("HUDShouldDraw", "agility_cl_HUDShouldDraw", function(name)
    if not cvar.EnableDamageIndicator:GetBool() and name == "CHudDamageIndicator" then
        return false
    end
end)