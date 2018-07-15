
include "agility/util.lua"

local function SetupEffect(pos, normal, target)
    local effect = EffectData()

    effect:SetEntity(target)
    effect:SetOrigin(pos)
    effect:SetStart(pos)
    effect:SetNormal(normal)

    return effect
end

local bloodDecalTraceLen = 10000
local bloodDecalDirOffsets = { 0, -0.25, -0.5, -0.75, -1 }

local function BloodEffect(color, pos, normal, target, impactData)
    pos = pos + normal * 5.0
    local effect = SetupEffect(pos, normal, target)

    effect:SetScale(10)
    effect:SetFlags(3)
    effect:SetColor(color)

    util.Effect("bloodspray", effect)

    effect:SetScale(25)
    util.Effect("BloodImpact", effect)
    
    local decal = color == 0 and "Blood" or "YellowBlood"

    for i, dirOffset in ipairs(bloodDecalDirOffsets) do
        local decalDir = impactData.Normal + Vector(0, 0, dirOffset)
        util.Decal(decal, pos, pos + decalDir * bloodDecalTraceLen, target)
    end
end

local effectsTable = {
    [MAT_CONCRETE] = function(pos, normal, target)
        pos = pos + normal * 5.0
        local effect = SetupEffect(pos, normal, target)

        effect:SetScale(20)

        util.Effect("WheelDust", effect)
    end,
    [MAT_DIRT] = function(pos, normal, target)

    end,
    [MAT_FLESH] = function(pos, normal, target, impactData)
        BloodEffect(0, pos, normal, target, impactData)
    end,
    [MAT_ALIENFLESH] = function(pos, normal, target, impactData)
        BloodEffect(1, pos, normal, target, impactData)
    end,
    [MAT_METAL] = function(pos, normal, target)
        local effect = SetupEffect(pos, normal, target)
        
        effect:SetScale(2)
        effect:SetMagnitude(4)
        effect:SetRadius(2)

        util.Effect("Sparks", effect)
    end,
    [MAT_PLASTIC] = function(pos, normal, target)
    
    end,
    [MAT_WOOD] = function(pos, normal, target)

    end,
    Default = function(pos, normal, target)

    end,
}

function ENT:CreateGeneralImpact(impactData)
    local effect = EffectData()
    effect:SetOrigin(impactData.HitPos + impactData.HitNormal)

    if IsValid(self.Attacker) then
        effect:SetStart(self.Attacker:EyePos())
    end

    effect:SetSurfaceProp(impactData.SurfaceProps)
    effect:SetDamageType(DMG_BULLET)
    effect:SetHitBox(impactData.HitBox)

    local ent = impactData.Entity
    effect:SetEntity(ent)
    effect:SetEntIndex(ent:EntIndex())

    util.Effect("Impact", effect)
end

function ENT:CreateImpactEffects(impactData)
    local pos = impactData.HitPos
    local normal = impactData.HitNormal
    local target = impactData.Entity
    local matType = impactData.MatType

    local effectsFunc = effectsTable[matType]
    if not effectsFunc then
        effectsFunc = effectsTable.Default
    end

    effectsFunc(pos, normal, target, impactData)
    self:CreateGeneralImpact(impactData)
end
