
include "shared.lua"

include "agility/util.lua"
cvar = include "agility/cvars.lua"

local tracerLen = 1000.0
local renderBounds = Vector(tracerLen, tracerLen, tracerLen)

function ENT:Initialize()
    self:SetRenderBounds(-renderBounds, renderBounds)
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

function ENT:Draw()
    self:DrawModel()
end