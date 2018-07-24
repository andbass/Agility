
include "shared.lua"

include "agility/util.lua"
cvar = include "agility/cvars.lua"

local tracerMat = Material("effects/spark")

local tracerWidth = 9.0
local tracerLen = 1000.0

local tracerColor = Vector(1.0, 0.8, 0.5)
local tracerColorPly = Vector(0.8, 1.0, 0.5)

local tracerMinSpeed = 1e3

local renderBounds = Vector(tracerLen, tracerLen, tracerLen)

function ENT:Initialize()
    self:SetRenderBounds(-renderBounds, renderBounds)
    self:DrawShadow(false)

    self:InitTracer()
end

function ENT:InitTracer()
    self.TracerColor = tracerColor

    local attacker = self:GetShooter()
    local ply = LocalPlayer()

    if ply == attacker then
        self.TracerColor = tracerColorPly
    end

    self.TracerColor = self.TracerColor:ToColor()
end

function ENT:OnRemove()
    local killEnt = self:GetKillEntity()
    if IsValid(killEnt) then
        for i, ragdoll in ipairs(ents.FindByClass("class C_ClientRagdoll")) do
            if killEnt == ragdoll:GetRagdollOwner() then
                self:ApplyRagdollForce(ragdoll)
            end
        end
    end
end

function ENT:ApplyRagdollForce(ragdoll)
    local bone = self:GetKillBone()
    local vel = self:GetKillVelocity()

    local phys = ragdoll:GetPhysicsObjectNum(bone)
    phys:ApplyForceCenter(vel * 5000.0)

    if bone == 10 then
        local regularBone = ragdoll:TranslatePhysBoneToBone(bone)
        ragdoll:ManipulateBoneScale(regularBone, Vector())
    end
end

function ENT:Tracer()
    local vel = self:GetVelocity()
    local speed = vel:Length()
    local dir = vel:GetNormalized()

    local lenModifier = (speed - tracerMinSpeed) * 5e-4
    lenModifier = math.max(lenModifier, 0)

    local frontTip = self:GetPos() + dir * tracerLen * 0.78 * lenModifier
    local backTip = frontTip - dir * tracerLen * lenModifier

    render.SetMaterial(tracerMat)
    render.DrawBeam(backTip, frontTip, tracerWidth, 0, 4, self.TracerColor)
end

function ENT:Draw()
    self:DrawModel()
end

function ENT:DrawTranslucent()
    self:Tracer()
end