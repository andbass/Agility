
include "agility/util.lua"
local cvar = include "agility/cvars.lua"

local ammoMultipliers = {
    Pistol = {
        Damage = 0.9,
        Force = 1.0,
    },
    Buckshot = {
        Damage = 0.65,
        Force = 1.5,
    },
    AR2 = {
        Damage = 0.75,
        Force = 1.0,
    },
    SMG1 = {
        Damage = 0.6,
        Force = 0.8,
    },
    ["357"] = {
        Damage = 2.0,
        Force = 2.5,
    }
}

local function IsHL2Swep(data)
    return data.Damage == 0 and data.Force == 1
end

local function ComputeMultipliers(data)
    if IsHL2Swep(data) then
        return ammoMultipliers[data.AmmoType] or {
            Damage = 1.0,
            Force = 1.0,
        }
    end

    return {
        Damage = math.log(data.Damage) * 0.5,
        Force = math.log(data.Force) * 0.5,
    }
end

hook.Add("EntityFireBullets", "agility_FireBullets", function(ent, data)
    if not cvar.BulletEnable:GetBool() then
        return true
    end

    local right = data.Dir:Cross(ent:GetUp())
    local up = data.Dir:Cross(right)

    right:Normalize()
    up:Normalize()

    local weapon = nil
    if IsValid(data.Attacker) and data.Attacker.GetActiveWeapon then
        weapon = data.Attacker:GetActiveWeapon()
    end

    local fromShotgun = false
    local multipliers = ComputeMultipliers(data)
    
    local speed = 3e3
    if data.Num > 3 then
        fromShotgun = true
        speed = speed * 0.75
    end

    for i = 1, data.Num do
        local ang = math.Rand(0, 2 * math.pi)
        local xDisp = math.cos(ang) * math.Rand(0, data.Spread.x)
        local yDisp = math.sin(ang) * math.Rand(0, data.Spread.y)

        local dir = data.Dir
        dir = dir + right * xDisp
        dir = dir + up * yDisp

        dir:Normalize()

        local bullet = ents.Create("bullet")
        if not IsValid(bullet) then
            return true
        end

        bullet.InitialSpeed = speed
        bullet.SpeedToDamage = 5e2
        bullet.LifeTime = 3.0

        bullet.Weapon = weapon
        bullet.FromShotgun = fromShotgun
        bullet.Multipliers = multipliers

        bullet:SetAttacker(ent)
        bullet:SetPos(data.Src - dir * 5.0)

        bullet:Spawn()
        bullet:SetDirection(dir)
    end

    return false
end)

hook.Add("ScaleNPCDamage", "agility_ScaleNPCDamage", function(npc, hitgroup, dmginfo)
    if cvar.BulletEnableDamageScale:GetBool() then
        if hitgroup == HITGROUP_HEAD then
            dmginfo:ScaleDamage(2.0)
        end
        
        return 0
    end
end)