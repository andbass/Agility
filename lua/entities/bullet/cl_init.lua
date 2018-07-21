
include "shared.lua"

include "agility/util.lua"
cvar = include "agility/cvars.lua"

local tracerMat = Material("effects/spark")

local tracerWidth = 10.0
local tracerLen = 800.0
local tracerColor = Color(255, 220, 150)
local tracerMinSpeed = 1e3

local renderBounds = Vector(tracerLen, tracerLen, tracerLen)

function ENT:Initialize()
    self:SetRenderBounds(-renderBounds, renderBounds)
    self:DrawShadow(false)
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
    render.DrawBeam(backTip, frontTip, tracerWidth, 0, 4, tracerColor)
end

function ENT:Draw()
    self:DrawModel()
end

function ENT:DrawTranslucent()
    self:Tracer()
end