
include "agility/util.lua"
local cvar = include "agility/cvars.lua"

ENT.PrintName = "Bad Bullet"
ENT.Type = "anim"

ENT.Spawnable = true
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
    self:NetworkVar("Vector", 0, "KillVelocity")
    self:NetworkVar("Int", 0, "KillBone")

    self:NetworkVar("Entity", 0, "KillEntity")
    self:NetworkVar("Entity", 1, "Shooter")
end
